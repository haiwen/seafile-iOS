//
//  SeafBaseOperation.m
//  Seafile
//
//  Created by henry on 2024/11/27.
//
#import "SeafBaseOperation.h"

@implementation SeafBaseOperation

@synthesize executing = _executing;
@synthesize finished = _finished;

- (instancetype)init {
    if (self = [super init]) {
        _executing = NO;
        _finished = NO;
        _taskList = [NSMutableArray array];
        _observersRemoved = NO;
        _operationCompleted = NO;

        _retryCount = 0;
        _maxRetryCount = 3; // Default maximum retry count, can be modified in subclasses
        _retryDelay = 5;    // Default retry delay, can be modified in subclasses
    }
    return self;
}

#pragma mark - NSOperation Overrides

- (BOOL)isAsynchronous {
    return YES;
}

- (BOOL)isExecuting {
    return _executing;
}

- (BOOL)isFinished {
    return _finished;
}

- (void)start {
    [self.taskList removeAllObjects];

    if (self.isCancelled) {
        [self completeOperation];
        return;
    }

    [self willChangeValueForKey:@"isExecuting"];
    _executing = YES;
    [self didChangeValueForKey:@"isExecuting"];

    // Subclasses need to start the actual operation here
}

- (void)cancel {
    @synchronized (self) {
        if (self.isCancelled) {
            return;
        }
        [super cancel];
        [self cancelAllRequests];
    }
}

- (void)cancelAllRequests {
    @synchronized (self.taskList) {
        for (NSURLSessionTask *task in self.taskList) {
            [task cancel];
        }
        [self.taskList removeAllObjects];
    }
}

#pragma mark - Operation State Management

- (void)completeOperation {
    @synchronized (self) {
        if (_operationCompleted) {
            return;
        }

        _operationCompleted = YES;

        [self willChangeValueForKey:@"isExecuting"];
        [self willChangeValueForKey:@"isFinished"];
        _executing = NO;
        _finished = YES;
        [self didChangeValueForKey:@"isFinished"];
        [self didChangeValueForKey:@"isExecuting"];
    }
}

- (void)addTaskToList:(NSURLSessionTask *)task {
    @synchronized (self.taskList) {
        [self.taskList addObject:task];
    }
}

#pragma mark - Retry Logic

- (BOOL)isRetryableError:(NSError *)error {
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case NSURLErrorTimedOut:
            case NSURLErrorCannotFindHost:
            case NSURLErrorCannotConnectToHost:
            case NSURLErrorNetworkConnectionLost:
            case NSURLErrorDNSLookupFailed:
            case NSURLErrorNotConnectedToInternet:
                return YES;
            default:
                return NO;
        }
    }
    return NO;
}

@end
