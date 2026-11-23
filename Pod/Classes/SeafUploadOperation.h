//
//  SeafUploadOperation.h
//  Pods
//
//  Created by henry on 2024/11/11.
//
#import <Foundation/Foundation.h>
#import "SeafAccountTaskQueue.h"
#import "SeafBaseOperation.h"

#define UPLOAD_RETRY_DELAY 5.0

@class SeafUploadFile;

/**
 * SeafUploadOperation handles the network operations for uploading files.
 * Files larger than 10 MiB are uploaded in resumable segments when the server
 * supports it (SeafResumableUploadSession); everything else, and every case the
 * resumable path declines, uses a single multipart request.
 */
@interface SeafUploadOperation : SeafBaseOperation

@property (nonatomic, strong) SeafUploadFile *uploadFile;

- (instancetype)initWithUploadFile:(SeafUploadFile *)uploadFile;

@property (nonatomic, assign) NSInteger retryCount;

@end
