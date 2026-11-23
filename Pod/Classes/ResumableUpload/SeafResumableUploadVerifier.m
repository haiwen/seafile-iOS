//
//  SeafResumableUploadVerifier.m
//  Seafile
//

#import "SeafResumableUploadVerifier.h"
#import "SeafResumableUploadPolicy.h"
#import "SeafConnection+ResumableUpload.h"

static const NSUInteger kConcurrentReads = 4;

@implementation SeafResumableUploadVerifier {
    // Strong while running: the sweeper has nothing else keeping it.
    SeafConnection *_connection;
    NSString *_repoId;
    NSString *_path;
    NSArray<SeafProbeWindow *> *_windows;

    dispatch_queue_t _queue;
    void (^_completion)(SeafResumableVerifyResult, NSError *);
    NSString *_url;
    NSUInteger _next;
    NSUInteger _pending;
    BOOL _mismatch;
    BOOL _unsupported;
    BOOL _failed;
    BOOL _done;
    NSError *_error;
    NSMutableArray<NSURLSessionTask *> *_tasks;
}

- (instancetype)initWithConnection:(SeafConnection *)connection
                            repoId:(NSString *)repoId
                              path:(NSString *)path
                           windows:(NSArray<SeafProbeWindow *> *)windows
{
    if (self = [super init]) {
        _connection = connection;
        _repoId = [repoId copy];
        _path = [path copy];
        _windows = [windows copy];
        _tasks = [NSMutableArray array];
    }
    return self;
}

- (void)startOnQueue:(dispatch_queue_t)queue
          completion:(void (^)(SeafResumableVerifyResult, NSError *))completion
{
    _queue = queue;
    _completion = [completion copy];
    if (_windows.count == 0) {
        dispatch_async(queue, ^{ [self finish:SeafResumableVerifyPassed]; });
        return;
    }
    SeafConnection *conn = _connection;
    NSString *repoId = _repoId, *path = _path;
    dispatch_async(dispatch_get_main_queue(), ^{
        [conn resumable_downloadURLInRepo:repoId path:path completion:^(NSString *url, NSInteger status, NSError *error) {
            dispatch_async(queue, ^{
                if (self->_done) return;
                if (url.length == 0) {
                    self->_error = error;
                    if ([SeafResumableUploadPolicy isCancellationError:error]) [self finish:SeafResumableVerifyCancelled];
                    else if (status == 404) [self finish:SeafResumableVerifyGone];
                    else [self finish:SeafResumableVerifyTransient];
                    return;
                }
                self->_url = url;
                [self pump];
            });
        }];
    });
}

- (void)cancel
{
    if (_done) return;
    _done = YES;
    _completion = nil;
    for (NSURLSessionTask *task in _tasks) [task cancel];
    [_tasks removeAllObjects];
    _connection = nil;
}

- (void)finish:(SeafResumableVerifyResult)result
{
    if (_done) return;
    _done = YES;
    void (^completion)(SeafResumableVerifyResult, NSError *) = _completion;
    _completion = nil;
    _connection = nil;
    if (completion) completion(result, _error);
}

- (void)pump
{
    if (_done) return;
    if (_mismatch || _unsupported || _failed) {
        // Wait for the reads in flight so nothing outlives the result.
        if (_pending > 0) return;
        [self finish:_mismatch ? SeafResumableVerifyMismatch
                    : _unsupported ? SeafResumableVerifyRangeUnsupported : SeafResumableVerifyTransient];
        return;
    }
    if (_next >= _windows.count) {
        if (_pending == 0) [self finish:SeafResumableVerifyPassed];
        return;
    }
    SeafConnection *conn = _connection;
    NSString *url = _url;
    dispatch_queue_t queue = _queue;
    while (_pending < kConcurrentReads && _next < _windows.count) {
        SeafProbeWindow *w = _windows[_next++];
        _pending++;
        dispatch_async(dispatch_get_main_queue(), ^{
            __block NSURLSessionTask *task = nil;
            task = [conn resumable_readRangeFromURL:url offset:w.offset length:w.length
                                         completion:^(NSData *data, NSInteger status, NSError *error) {
                dispatch_async(queue, ^{
                    if (task) [self->_tasks removeObject:task];
                    if (self->_done) return;
                    self->_pending--;
                    if (status == 206 && data.length == w.length) {
                        if (![w matchesData:data]) self->_mismatch = YES;
                    } else if (status == 200) {
                        self->_unsupported = YES;
                    } else {
                        // Includes a short 206: the read broke off, not the file.
                        self->_failed = YES;
                        self->_error = error;
                    }
                    [self pump];
                });
            }];
            if (task) {
                dispatch_async(queue, ^{
                    if (self->_done) [task cancel];
                    else [self->_tasks addObject:task];
                });
            }
        });
    }
}

@end
