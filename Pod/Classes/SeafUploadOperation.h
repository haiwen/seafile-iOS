//
//  SeafUploadOperation.h
//  Pods
//
//  Created by henry on 2024/11/11.
//
#import <Foundation/Foundation.h>
#import "SeafAccountTaskQueue.h"
#import "SeafBaseOperation.h"

#define UPLOAD_RETRY_DELAY 5

@class SeafUploadFile;

/**
 * SeafUploadOperation handles the network operations for uploading files.
 */
@interface SeafUploadOperation : SeafBaseOperation

@property (nonatomic, strong) SeafUploadFile *uploadFile;

- (instancetype)initWithUploadFile:(SeafUploadFile *)uploadFile;

@end
