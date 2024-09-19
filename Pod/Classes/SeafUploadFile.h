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

/// A protocol to handle upload progress and completion updates.
@protocol SeafUploadDelegate <NSObject>
- (void)uploadProgress:(SeafUploadFile *)file progress:(float)progress;
- (void)uploadComplete:(BOOL)success file:(SeafUploadFile *)file oid:(NSString *)oid;
@end

/**
 * The SeafUploadFile class represents a file upload task in the Seafile service, implementing preview capabilities and conforming to various protocols for file operations and task management.
 */
@interface SeafUploadFile : NSObject<SeafPreView, QLPreviewItem, SeafTask>

@property (readonly) NSString *lpath;/// The local path of the file to be uploaded.

@property (readonly) NSString *name;
@property (readonly) long long filesize;

@property (nonatomic, readonly, getter=isUploaded) BOOL uploaded;
@property (nonatomic, readonly, getter=isUploading) BOOL uploading;

@property (readwrite) BOOL overwrite;
@property (nonatomic, readonly) PHAsset *asset;/// The associated PHAsset, if the file is a photo from the photo library.

@property (nonatomic, readonly) NSURL *assetURL;/// The URL of the asset in the photo library.

@property (nonatomic, readonly) NSString *assetIdentifier;/// The unique identifier of the asset.

@property (readwrite) BOOL autoSync;/// Whether the upload should be automatically retried upon failure.

@property (readonly) float uProgress;/// Current upload progress as a float between 0 and 1.

@property (nonatomic, weak) id<SeafUploadDelegate> delegate;/// Delegate to handle progress and completion updates.

@property (nonatomic) SeafUploadCompletionBlock completionBlock;

@property (nonatomic, strong, readwrite) SeafDir *udir;/// The directory in which this file will be uploaded.

@property (nonatomic, strong) UIImage *previewImage;//NSItemProvider previewImage

@property (nonatomic, assign, getter=isStarred) BOOL starred;

@property (nonatomic, assign) NSTimeInterval uploadStartedTime;

/**
 * Initializes a SeafUploadFile with a local path.
 * @param lpath The local path of the file to be uploaded.
 * @return An instance of SeafUploadFile.
 */
- (id)initWithPath:(NSString *)lpath;

/**
 * Sets the associated PHAsset and its URL.
 * @param asset The PHAsset to associate with this upload.
 * @param url The URL of the asset in the photo library.
 */
- (void)setPHAsset:(PHAsset *)asset url:(NSURL *)url;

/**
 * Waits for the upload task to complete.
 * @return YES if the file was uploaded successfully, NO otherwise.
 */
- (BOOL)waitUpload;

/**
 * Cleans up resources associated with the file once it has been uploaded.
 */
- (void)cleanup;

/**
 * Asynchronously get photo library images.
 */
- (void)iconWithCompletion:(void (^)(UIImage *image))completion;
@end
