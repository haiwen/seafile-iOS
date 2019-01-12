//
//  SeafUploadFile.h
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuickLook/QuickLook.h>
#import <Photos/Photos.h>

#import "SeafPreView.h"
#import "SeafTaskQueue.h"

@class SeafConnection;
@class SeafUploadFile;
@class SeafDir;

typedef void (^SeafUploadCompletionBlock)(SeafUploadFile *file, NSString *oid, NSError *error);

@protocol SeafUploadDelegate <NSObject>
- (void)uploadProgress:(SeafUploadFile *)file progress:(float)progress;
- (void)uploadComplete:(BOOL)success file:(SeafUploadFile *)file oid:(NSString *)oid;
@end

@interface SeafUploadFile : NSObject<SeafPreView, QLPreviewItem, SeafTask>

@property (readonly) NSString *lpath;
@property (readonly) NSString *name;
@property (readonly) long long filesize;

@property (nonatomic, readonly, getter=isUploaded) BOOL uploaded;
@property (nonatomic, readonly, getter=isUploading) BOOL uploading;

@property (readwrite) BOOL overwrite;
@property (nonatomic, readonly) PHAsset *asset;
@property (nonatomic, readonly) NSURL *assetURL;
@property (nonatomic, readonly) NSString *assetIdentifier;
@property (readwrite) BOOL autoSync;

@property (readonly) float uProgress;
@property (nonatomic) id<SeafUploadDelegate> delegate;
@property (nonatomic) SeafUploadCompletionBlock completionBlock;

@property (readwrite) SeafDir *udir;
@property (nonatomic, strong) UIImage *previewImage;//NSItemProvider previewImage

@property (nonatomic, assign, getter=isStarred) BOOL starred;

- (id)initWithPath:(NSString *)lpath;

- (void)setPHAsset:(PHAsset *)asset url:(NSURL *)url;

- (BOOL)waitUpload;

- (void)cleanup;
@end
