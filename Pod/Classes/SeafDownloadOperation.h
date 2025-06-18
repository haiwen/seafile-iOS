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

@property (nonatomic, weak) SeafFile *file;
@property (nonatomic, strong) NSArray *blkids;
@property (nonatomic, strong) NSString *downloadingFileOid;
@property (nonatomic, assign) int currentBlockIndex;
@property (nonatomic) float progress;
@property (nonatomic, strong) NSError * _Nullable error;

// Download status related properties
@property (nonatomic, strong) NSMutableArray<NSURLSessionTask *> *taskList;

- (instancetype)initWithFile:(SeafFile *)file;

@end

