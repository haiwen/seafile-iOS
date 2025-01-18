//
//  SeafTaskProtocol.h
//  Pods
//
//  Created by henry on 2025/1/10.
//

// SeafTaskProtocol.h

#import <Foundation/Foundation.h>

// Task related constants
#define DEFAULT_CONCURRENCY 3
#define DEFAULT_RETRYCOUNT 3
#define Default_FileThumb_RetryCount 3
#define DEFAULT_ATTEMPT_INTERVAL 60 // 1 min
#define DEFAULT_COMPLELE_INTERVAL 3*60 // 3 min

// Task blocks
//typedef void (^TaskCompleteBlock)(id task, BOOL result);
typedef void (^TaskProgressBlock)(id task, float progress);

// Task protocol
@protocol SeafTask<NSObject>
@property NSTimeInterval lastFinishTimestamp;
@property (nonatomic) NSInteger retryCount;
@property (nonatomic) BOOL retryable;

- (NSString *)accountIdentifier;
- (NSString *)name;
- (void)cancel;
- (void)setTaskProgressBlock:(TaskProgressBlock)taskProgressBlock;

@optional
- (void)cleanup;
@end
