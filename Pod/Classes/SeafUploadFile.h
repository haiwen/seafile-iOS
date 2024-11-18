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

@property (nonatomic, copy) NSString *lpath;/// The local path of the file to be uploaded.

@property (readonly) NSString *name;
@property (nonatomic, assign) long long filesize;

@property (nonatomic, assign, getter=isUploaded) BOOL uploaded;
@property (nonatomic, assign, getter=isUploading) BOOL uploading;

@property (readwrite) BOOL overwrite;
@property (nonatomic, readonly) PHAsset *asset;/// The associated PHAsset, if the file is a photo from the photo library.

@property (nonatomic, readonly) NSURL *assetURL;/// The URL of the asset in the photo library.

@property (nonatomic, copy) NSString *assetIdentifier;/// The unique identifier of the asset.

@property (readwrite) BOOL uploadFileAutoSync;/// Whether the uploadFile is added from autoSync photo album.

@property (readonly) float uProgress;/// Current upload progress as a float between 0 and 1.

@property (nonatomic, weak) id<SeafUploadDelegate> delegate;/// Delegate to handle progress and completion updates.

@property (nonatomic, weak) id<SeafUploadDelegate> staredFileDelegate;/// Delegate to handle progress and completion for starred view.

@property (nonatomic) SeafUploadCompletionBlock completionBlock;

@property (nonatomic, strong, readwrite) SeafDir *udir;/// The directory in which this file will be uploaded.

@property (nonatomic, strong) UIImage *previewImage;//NSItemProvider previewImage

@property (nonatomic, assign, getter=isStarred) BOOL starred;

@property (nonatomic, assign) NSTimeInterval uploadStartedTime;

@property (nonatomic, assign) BOOL isEditedFile;//is edited from Seafile

@property (nonatomic, copy) NSString *editedFileRepoId;//the edited Seafile repoId

@property (nonatomic, copy) NSString *editedFilePath;//the edited Seafile path

@property (nonatomic, copy) NSString *editedFileOid;//the edited Seafile oid

@property (assign, nonatomic) BOOL shouldShowUploadFailure; // When modifying the file and uploading again during the upload editing process, do not show the upload failure dialog

//the error after operation
@property (nonatomic, strong, nullable) NSError *uploadError;

@property (strong) NSProgress * _Nullable progress;

@property (strong) NSArray * _Nullable missingblocks;
@property (strong) NSArray * _Nullable allblocks;
@property (strong) NSString * _Nullable commiturl;
@property (strong) NSString * _Nullable rawblksurl;
@property (strong) NSString * _Nullable uploadpath;
@property (nonatomic, strong) NSString * _Nullable blockDir;
@property long blkidx;


/**
 * Initializes a SeafUploadFile with a local path.
 * @param lpath The local path of the file to be uploaded.
 * @return An instance of SeafUploadFile.
 */
- (id _Nullable )initWithPath:(NSString *_Nullable)lpath;

/**
 * Sets the associated PHAsset and its URL.
 * @param asset The PHAsset to associate with this upload.
 * @param url The URL of the asset in the photo library.
 */
- (void)setPHAsset:(PHAsset *_Nullable)asset url:(NSURL *_Nullable)url;

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
- (void)iconWithCompletion:(void (^_Nullable)(UIImage * _Nullable image))completion;

// Prepare for upload
- (void)prepareForUploadWithCompletion:(void (^_Nullable)(BOOL success, NSError * _Nullable error))completion;

- (void)finishUpload:(BOOL)result oid:(NSString *_Nullable)oid error:(NSError *_Nullable)error;

- (void)updateProgress:(NSProgress *_Nullable)progress;

-(void)updateProgressWithoutKVO:(NSProgress *_Nullable)progress;

@end
