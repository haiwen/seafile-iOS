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
#import "SeafTaskProtocol.h"

@class SeafConnection;
@class SeafUploadFile;
@class SeafDir;
@class SeafUploadFileModel;
@class SeafAssetManager;
@class SeafPreviewManager;

typedef void (^SeafUploadCompletionBlock)(SeafUploadFile *file, NSString *oid, NSError *error);

/// A protocol to handle upload progress and completion updates.
@protocol SeafUploadDelegate <NSObject>
- (void)uploadProgress:(SeafUploadFile *)file progress:(float)progress;
- (void)uploadComplete:(BOOL)success file:(SeafUploadFile *)file oid:(NSString *)oid;
@end

/**
 * The SeafUploadFile class represents a file upload task in the Seafile service, implementing preview capabilities and conforming to various protocols for file operations and task management.
 */
@interface SeafUploadFile : NSObject <SeafPreView, QLPreviewItem, SeafTask>

// Model and Managers
@property (nonatomic, strong) SeafUploadFileModel *model;
@property (nonatomic, strong) SeafAssetManager *assetManager;

// Delegates and Blocks
@property (nonatomic, weak) id<SeafUploadDelegate> delegate;
@property (nonatomic, weak) id<SeafUploadDelegate> staredFileDelegate;
@property (nonatomic, copy) SeafUploadCompletionBlock completionBlock;
@property (nonatomic, copy) TaskProgressBlock taskProgressBlock;

// Upload Related
@property (nonatomic, strong) SeafDir *udir;
@property (nonatomic, strong) NSError *uploadError;
@property (nonatomic, strong) NSURLSessionUploadTask *task;
@property (nonatomic, strong) NSProgress *progress;
@property (nonatomic) dispatch_semaphore_t semaphore;

// Convenience Properties (forwarded to model)
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *lpath;
@property (nonatomic, readonly) long long filesize;
@property (nonatomic, readonly) float uProgress;
@property (nonatomic, readonly) BOOL uploading;
@property (nonatomic, readonly) BOOL uploaded;
@property (nonatomic, readonly) BOOL overwrite;
@property (nonatomic, readonly) PHAsset *asset;
@property (nonatomic, readonly) NSString *assetIdentifier;
@property (nonatomic, readonly) BOOL uploadFileAutoSync;
@property (nonatomic, readonly) BOOL starred;
@property (nonatomic, readonly) BOOL isEditedFile;
@property (nonatomic, readonly) NSString *editedFileRepoId;
@property (nonatomic, readonly) NSString *editedFilePath;
@property (nonatomic, readonly) NSString *editedFileOid;
@property (nonatomic, readonly) BOOL shouldShowUploadFailure;

@property (nonatomic, strong) NSDate * _Nullable lastModified;

// SeafTask Protocol Properties
@property (nonatomic) NSTimeInterval lastFinishTimestamp;
@property (nonatomic) NSInteger retryCount;
@property (nonatomic) BOOL retryable;

@property (nonatomic, strong) UIImage *previewImage;

/**
 * Initializes a SeafUploadFile with a local path.
 * @param path The local path of the file to be uploaded.
 * @return An instance of SeafUploadFile.
 */
- (instancetype)initWithPath:(NSString *)path;

/**
 * Sets the associated PHAsset and its URL.
 * @param asset The PHAsset to associate with this upload.
 * @param url The URL of the asset in the photo library.
 */
- (void)setPHAsset:(PHAsset *)asset url:(NSURL *)url;

/**
 * Cleans up resources associated with the file once it has been uploaded.
 */
- (void)cleanup;

/**
 * Asynchronously get photo library images.
 */
- (void)iconWithCompletion:(void (^_Nullable)(UIImage * _Nullable image))completion;

/**
 * Asynchronously gets the NSData for the associated PHAsset.
 * @param completion A block to be executed when the data retrieval is complete.
 *                   The block takes two arguments: the retrieved NSData (or nil on error/no asset)
 *                   and an NSError object (or nil on success).
 */
- (void)getDataForAssociatedAssetWithCompletion:(void (^_Nullable)(NSData * _Nullable data, NSError * _Nullable error))completion;

// Prepare for upload
- (void)prepareForUploadWithCompletion:(void (^_Nonnull)(BOOL success, NSError * _Nonnull error))completion;

- (void)finishUpload:(BOOL)result oid:(NSString *_Nonnull)oid error:(NSError *_Nonnull)error;

// Update progress bar
- (void)uploadProgress:(float)progress;

// Public Methods
- (void)cancel;

// Class Methods
+ (void)clearCache;

// ============ Restored old uploadHeic method ============
- (BOOL)uploadHeic;
// - (BOOL)uploadLivePhoto;  // Motion Photo functionality temporarily disabled

- (BOOL)waitUpload;

- (void)getImageWithCompletion:(void (^)(UIImage *image))completion;

@end
