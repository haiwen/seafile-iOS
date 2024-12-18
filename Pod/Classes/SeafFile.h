//
//  SeafFile.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <QuickLook/QuickLook.h>
#import "SeafConnection.h"
#import "SeafUploadFile.h"
#import "SeafBase.h"
#import "Utils.h"

#define THUMB_SIZE 96

@class SeafFile;
/**
 * Completion block for download operations.
 * @param file The file being downloaded.
 * @param error Error information if the download failed, otherwise nil.
 */
typedef void (^SeafDownloadCompletionBlock)(SeafFile* _Nonnull file, NSError * _Nullable error);

/**
 * Completion block for thumbnail download operations.
 * @param ret Indicates whether the thumbnail was successfully downloaded.
 */
typedef void (^SeafThumbCompleteBlock)(BOOL ret);

/**
 * Delegate protocol to handle file upload updates.
 */
@protocol SeafFileUpdateDelegate <NSObject>
- (void)updateProgress:(nonnull SeafFile * )file progress:(float)progress;
- (void)updateComplete:(nonnull SeafFile * )file result:(BOOL)res;

@end

/**
 * Represents a file in Seafile.
 */
@interface SeafFile : SeafBase<QLPreviewItem, SeafPreView, SeafUploadDelegate, SeafTask> {
@protected
    long long _filesize;///< File size in bytes.
    long long _mtime;///< Modification time.
    NSString *_shareLink;///< Share link of the file.
}

/**
 * Initializes a new SeafFile with the specified parameters.
 * @param aConnection The SeafConnection instance associated with this file.
 * @param anId The object identifier.
 * @param aRepoId Repository identifier where the file is stored.
 * @param aName Name of the file.
 * @param aPath Path to the file in the repository.
 * @param mtime Last modification time.
 * @param size Size of the file in bytes.
 * @return An instance of SeafFile.
 */
- (nonnull id)initWithConnection:(nonnull SeafConnection *)aConnection
                     oid:(nullable NSString *)anId
                  repoId:(nonnull NSString *)aRepoId
                    name:(nonnull NSString *)aName
                    path:(nonnull NSString *)aPath
                   mtime:(long long)mtime
                    size:(unsigned long long)size;

@property (strong, nonatomic, nullable) NSString *mpath;// For modified files
@property (readonly, nullable) NSString *detailText;///< A string providing detailed information about the file.
@property (readonly) long long filesize;///< Getter for file size.
@property (readonly) long long mtime;///< Getter for last modification time.
@property (strong, nullable) id <SeafFileUpdateDelegate> udelegate;///< The delegate for upload updates.
@property (strong, nonatomic) NSProgress * _Nullable progress;///< Progress of the ongoing file operation.
@property (nonatomic, readonly, getter=isUploaded) BOOL uploaded;///< Whether the file is uploaded.
@property (nonatomic, readonly, getter=isUploading) BOOL uploading;///< Whether the file is currently uploading.
@property (copy, nonatomic) NSString * _Nullable thumbnailURLStr;//image thumbnail Url String
//@property (nonatomic, assign) NSInteger thumbFailedCount;//download thumb failure count
@property (nonatomic, copy) NSURLSessionDownloadTask * _Nullable thumbtask;
@property (strong, nonatomic) SeafUploadFile * _Nullable ufile;
@property (assign, nonatomic) BOOL isDownloading;// Checks if the file is currently being downloaded.
@property (assign, nonatomic) BOOL downloaded;// Checks if the file is downloaded.

@property (strong) NSString * _Nullable downloadingFileOid;
@property NSURLSessionDownloadTask * _Nullable task;
@property (strong) NSArray *blkids;
@property int index;

//@property (assign, nonatomic) BOOL isTaskCanceled;


///**
// * Checks if the file is currently being downloaded.
// * @return YES if the file is downloading, otherwise NO.
// */
//- (BOOL)isDownloading;

/**
 * Checks if the file is starred.
 * @return YES if the file is starred, otherwise NO.
 */
- (BOOL)isStarred;

/**
 * Deletes the local cache of the file.
 */
- (void)deleteCache;

/**
 * Initiates an update of the file with a delegate.
 * @param dg The delegate to handle file update events.
 */
- (void)update:(nullable id<SeafFileUpdateDelegate>)dg;

/**
 * Converts file data to a dictionary.
 * @return NSDictionary containing file information.
 */
- (nonnull NSDictionary *)toDict;

/**
 * Returns the cache path of the file.
 * @return The local cache path.
 */
- (nullable NSString *)cachePath;

/**
 * Sets a completion block to be executed when thumbnail download finishes.
 * @param block The completion block.
 */
- (void)setThumbCompleteBlock:(nullable SeafThumbCompleteBlock)block;

/**
 * Sets a completion block to be executed when file download is complete.
 * @param block The completion block.
 */
- (void)setFileDownloadedBlock:(nullable SeafDownloadCompletionBlock)block;

/**
 * Sets a completion block to be executed when file upload is complete.
 * @param block The completion block.
 */
- (void)setFileUploadedBlock:(nullable SeafUploadCompletionBlock)block;

/**
 * Initiates the download of the file's thumbnail.
 * @param completeBlock A block to execute when the thumbnail download is complete.
 */
- (void)downloadThumb:(SeafThumbCompleteBlock _Nonnull)completeBlock;

/**
 * Cancels any ongoing thumbnail download.
 */
- (void)cancelThumb;

/**
 * Cancels the thumb which not download complete.
 */
- (void)cancelNotDisplayThumb;

/**
 * Uploads the file from a specified URL.
 * @param url The URL of the file to upload.
 * @return YES if the upload was initiated successfully, otherwise NO.
 */
- (BOOL)uploadFromFile:(NSURL *_Nonnull)url;

/**
 * Waits for the upload to complete.
 * @return YES if the upload completed, otherwise NO.
 */
- (BOOL)waitUpload;

/**
 * Saves the modified version of a file from a temporary preview URL to the local cache.
 * @param url The URL of the modified file.
 * @return YES if the file was successfully saved to the local cache, otherwise NO.
 */
- (BOOL)saveEditedPreviewFile:(NSURL *_Nullable)url;

/**
 * Gets the path for the thumbnail of the file.
 * @param objId The object identifier for which the thumbnail is requested.
 * @return The path to the thumbnail.
 */
- (NSString *_Nullable)thumbPath:(NSString *_Nullable)objId;

- (NSString *_Nullable)starredDetailText;

- (void)getImageWithCompletion:(void (^_Nullable)(UIImage * _Nullable image))completion;

- (NSString *_Nullable)downloadTempPath:(NSString *_Nullable)objId;

- (void)downloadProgress:(float)progress;

- (void)finishDownload:(NSString *_Nullable)ooid;

- (void)failedDownload:(NSError *_Nullable)error;

- (void)downloadBlocks;

- (void)finishDownloadThumb:(BOOL)success;

- (void)removeBlock:(NSString *)blkId;

@end
