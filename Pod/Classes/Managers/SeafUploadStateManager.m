#import "SeafUploadStateManager.h"
#import "SeafUploadFile.h"
#import "Debug.h"

@interface SeafUploadStateManager ()
@property (nonatomic, strong) NSMutableDictionary *uploadStates;
@end

@implementation SeafUploadStateManager

+ (instancetype)sharedInstance {
    static SeafUploadStateManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _uploadStates = [NSMutableDictionary new];
    }
    return self;
}

- (void)cancelUpload:(SeafUploadFile *)file {
    @synchronized(self.uploadStates) {
        [self.uploadStates removeObjectForKey:file.lpath];
    }
    [file cancel];
}

- (void)finishUpload:(SeafUploadFile *)file withResult:(BOOL)result oid:(NSString *)oid error:(NSError *)error {
    @synchronized(self.uploadStates) {
        NSMutableDictionary *state = [self getOrCreateStateForFile:file];
        state[@"uploaded"] = @(result);
        state[@"uploading"] = @(NO);
        state[@"oid"] = oid;
        state[@"error"] = error;
        if (result) {
            state[@"progress"] = @(1.0);
        }
    }
    Debug("Finish upload file %@ with result: %d, oid: %@, error: %@", file.name, result, oid, error);
}

- (void)saveUploadFileToStorage:(SeafUploadFile *)file {
    @synchronized(self.uploadStates) {
        NSMutableDictionary *state = [self getOrCreateStateForFile:file];
        [state setObject:@(YES) forKey:@"saved"];
    }
}

- (void)updateUploadProgress:(SeafUploadFile *)file progress:(float)progress {
    @synchronized(self.uploadStates) {
        NSMutableDictionary *state = [self getOrCreateStateForFile:file];
        state[@"progress"] = @(progress);
        state[@"uploading"] = @(YES);
    }
}

#pragma mark - Private Methods

- (NSMutableDictionary *)getOrCreateStateForFile:(SeafUploadFile *)file {
    NSMutableDictionary *state = self.uploadStates[file.lpath];
    if (!state) {
        state = [NSMutableDictionary dictionary];
        self.uploadStates[file.lpath] = state;
    }
    return state;
}

@end 