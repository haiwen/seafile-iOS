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

/**
 上传分块相关属性
 */
@property (nonatomic, strong, nullable) NSArray<NSString *> *missingBlocks;
@property (nonatomic, strong, nullable) NSArray<NSString *> *allBlocks;
@property (nonatomic, copy, nullable) NSString *rawBlksUrl;
@property (nonatomic, copy, nullable) NSString *commitUrl;
@property (strong) NSString * _Nullable uploadpath;
@property long blkidx;
@property (nonatomic, strong) NSString * _Nullable blockDir;

@end
