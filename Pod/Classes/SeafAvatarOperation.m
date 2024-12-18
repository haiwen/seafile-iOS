//
//  SeafAvatarOperation.m
//  Seafile
//
//  Created by henry on 2024/11/11.
//
#import "SeafAvatarOperation.h"
#import "SeafAvatar.h"
#import "SeafConnection.h"
#import "Utils.h"
#import "Debug.h"

@interface SeafAvatarOperation ()

@property (nonatomic, assign) BOOL executing;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL operationCompleted;

//@property (strong) NSURLSessionDownloadTask *task;
@property (nonatomic, strong) NSMutableArray<NSURLSessionTask *> *taskList;

@end

@implementation SeafAvatarOperation

@synthesize executing = _executing;
@synthesize finished = _finished;

- (instancetype)initWithAvatar:(SeafAvatar *)avatar
{
    if (self = [super init]) {
        _avatar = avatar;
        _executing = NO;
        _finished = NO;
        _taskList = [NSMutableArray array];
        _operationCompleted = NO;
    }
    return self;
}

#pragma mark - NSOperation Overrides

- (BOOL)isAsynchronous
{
    return YES;
}

- (BOOL)isExecuting
{
    return _executing;
}

- (BOOL)isFinished
{
    return _finished;
}

- (void)start
{
    [self.taskList removeAllObjects];
    
    if (self.isCancelled || self.operationCompleted) {
        [self completeOperation];
        return;
    }

    [self willChangeValueForKey:@"isExecuting"];
    _executing = YES;
    [self didChangeValueForKey:@"isExecuting"];

    [self beginDownload];
}

- (void)cancel
{
    [super cancel];
    [self cancelAllRequests];
    if (self.isExecuting && !_operationCompleted) {
        [self completeOperation];
    }
}

- (void)cancelAllRequests
{
    for (NSURLSessionTask *task in self.taskList) {
        [task cancel];
    }
    [self.taskList removeAllObjects];
}

#pragma mark - Download Logic

- (void)beginDownload
{
    if (self.isCancelled || self.operationCompleted) {
        [self completeOperation];
        return;
    }

    SeafConnection *connection = self.avatar.connection;

    [self downloadAvatarWithConnection:connection];
}

- (void)downloadAvatarWithConnection:(SeafConnection *)connection
{
    NSURLSessionDataTask *connectionTask = [connection sendRequest:self.avatar.avatarUrl success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id  _Nonnull JSON) {
        if (![JSON isKindOfClass:[NSDictionary class]]) {
            NSError *error = [NSError errorWithDomain:@"com.seafile.error"
                                           code:-1
                                       userInfo:@{ NSLocalizedDescriptionKey: @"JSON format is incorrect" }];
            [self finishDownload:false error:error];
            return;
        }
        NSString *url = [JSON objectForKey:@"url"];
        if (!url) {
            NSError *error = [NSError errorWithDomain:@"com.seafile.error"
                                           code:-1
                                       userInfo:@{ NSLocalizedDescriptionKey: @"JSON format is incorrect" }];
            [self finishDownload:false error:error];
            return;
        }
        if([[JSON objectForKey:@"is_default"] integerValue]) {
            if ([[SeafAvatar avatarAttrs] objectForKey:self.avatar.path])
                [[SeafAvatar avatarAttrs] removeObjectForKey:self.avatar.path];
            [self finishDownload:true error:nil];
            return;
        }
        if (![self.avatar modified:[[JSON objectForKey:@"mtime"] integerValue:0]]) {
            Debug("avatar not modified\n");
            [self finishDownload:true error:nil];
            return;
        }
        
        url = [[url stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] escapedUrlPath];;
        NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
        NSURLSessionDownloadTask *task = [connection.sessionMgr downloadTaskWithRequest:downloadRequest progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
            return [NSURL fileURLWithPath:self.avatar.path];
        } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
            if (error) {
                Debug("Failed to download avatar url=%@, error=%@",downloadRequest.URL, [error localizedDescription]);
                [self finishDownload:false error:error];
            } else {
                Debug("Successfully downloaded avatar: %@ from %@", filePath, url);
                if (![filePath.path isEqualToString:self.avatar.path]) {
                    [[NSFileManager defaultManager] removeItemAtPath:self.avatar.path error:nil];
                    [[NSFileManager defaultManager] moveItemAtPath:filePath.path toPath:self.avatar.path error:nil];
                }
                NSMutableDictionary *attr = [[SeafAvatar avatarAttrs] objectForKey:self.avatar.path];
                if (!attr) attr = [[NSMutableDictionary alloc] init];
                [Utils dict:attr setObject:[JSON objectForKey:@"mtime"] forKey:@"mtime"];
                [self.avatar saveAttrs:attr];
                [SeafAvatar saveAvatarAttrs];
                [self finishDownload:true error:nil];
            }
        }];
        [task resume];
        [self.taskList addObject:task];
    } failure:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id  _Nullable JSON, NSError * _Nullable error) {
        Warning("Failed to download avatar from %@", request.URL);
        [self finishDownload:false error:error];
    }];
    [self.taskList addObject:connectionTask];
}

- (void)finishDownload:(BOOL)success error:(NSError *)error {
    if (error) {
        Debug("avartar download failed = %@", error);
    }
    
    [self.avatar downloadComplete:success];
    
    [self completeOperation];
}

#pragma mark - Operation State Management

- (void)completeOperation {
    if (_operationCompleted) {
        return; // If already completed, do not repeat
    }
    _operationCompleted = YES;
    
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    _executing = NO;
    _finished = YES;
    [self didChangeValueForKey:@"isFinished"];
    [self didChangeValueForKey:@"isExecuting"];
}

@end
