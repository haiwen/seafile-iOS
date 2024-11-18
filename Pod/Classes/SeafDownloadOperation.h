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

- (instancetype)initWithFile:(SeafFile *)file;

@end

