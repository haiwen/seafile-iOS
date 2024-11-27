//
//  SeafBaseOperation.h
//  Seafile
//
//  Created by henry on 2024/11/27.
//

#import <Foundation/Foundation.h>

@interface SeafBaseOperation : NSOperation

//@property (nonatomic, assign) BOOL executing;
//@property (nonatomic, assign) BOOL finished;

@property (nonatomic, strong) NSMutableArray<NSURLSessionTask *> *taskList;
@property (nonatomic, assign) BOOL observersRemoved;
@property (nonatomic, assign) BOOL observersAdded;

@property (nonatomic, assign) BOOL operationCompleted;

@property (nonatomic, assign) NSInteger retryCount;
@property (nonatomic, assign) NSInteger maxRetryCount;
@property (nonatomic, assign) NSTimeInterval retryDelay;

- (void)cancelAllRequests;
- (void)completeOperation;
- (BOOL)isRetryableError:(NSError *)error;

@end

