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
@property (nonatomic, strong) NSError *error;
@property (nonatomic, assign) float progress;

// Download status related properties
@property (nonatomic, strong) NSString *downloadingFileOid;
@property (nonatomic, strong) NSArray *blkids;
@property (nonatomic, assign) int currentBlockIndex;
@property (nonatomic, strong) NSMutableArray<NSURLSessionTask *> *taskList;

- (instancetype)initWithFile:(SeafFile *)file;

@end

