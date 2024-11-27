//
//  SeafDownloadOperation.h
//  Pods
//
//  Created by henry on 2024/11/11.
//

#import <Foundation/Foundation.h>
#import "SeafAccountTaskQueue.h"
#import "SeafBaseOperation.h"

@class SeafFile;

/**
 * SeafDownloadOperation handles the network operations for downloading files.
 */
@interface SeafDownloadOperation : SeafBaseOperation

@property (nonatomic, strong) SeafFile *file;

//@property (nonatomic, assign) BOOL observersRemoved;
//@property (nonatomic, assign) BOOL observersAdded;

//@property (nonatomic, assign) NSInteger retryCount;
//@property (nonatomic, assign) NSInteger maxRetryCount;
//@property (nonatomic, assign) NSTimeInterval retryDelay;

- (instancetype)initWithFile:(SeafFile *)file;

@end

