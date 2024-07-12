//
//  SeafPhotoBackupTool.h
//  Seafile
//
//  Created by three on 2024/1/25.
//

#import <Foundation/Foundation.h>

@class SeafConnection;
@class SeafDir;

/**
 Protocol defining methods for responding to photo synchronization events.
 */
@protocol SeafPhotoSyncWatcherDelegate <NSObject>

/**
 Called when the number of photos pending synchronization changes.
 @param remain Number of photos remaining to be synced.
 */
- (void)photoSyncChanged:(long)remain;
@end

/**
 A utility class for backing up photos to a Seafile server.
 */
@interface SeafPhotoBackupTool : NSObject

/// The SeafConnection object managing network operations.
@property (nonatomic, strong) SeafConnection * _Nonnull connection;

/// The directory on the server where photos will be uploaded.
@property (nonatomic, strong) SeafDir * _Nullable syncDir;

/// Delegate object to receive photo synchronization change notifications.
@property (weak) id<SeafPhotoSyncWatcherDelegate> _Nullable photSyncWatcher;

/// An array containing the identifiers of photos queued for synchronization.
@property (nonatomic, strong) NSMutableArray * _Nullable photosArray;

/// An array containing the identifiers of photos currently being uploaded.
@property (nonatomic, strong) NSMutableArray * _Nullable uploadingArray;

/// A Boolean value indicating whether automatic syncing is enabled.
@property (nonatomic, assign) BOOL inAutoSync;

/// A Boolean value indicating whether the tool is currently checking the photo library.
@property (nonatomic, assign) BOOL inCheckPhotoss;

/**
 Initializes a SeafPhotoBackupTool object with the specified SeafConnection and local upload directory.
 @param connection A SeafConnection object.
 @param localUploadDir The local directory path where photos will be temporarily stored before uploading.
 @return An initialized SeafPhotoBackupTool object or nil if the object couldn't be created.
 */
- (instancetype _Nonnull )initWithConnection:(SeafConnection * _Nonnull)connection andLocalUploadDir:(NSString * _Nonnull)localUploadDir;

/**
 Starts a check to identify new photos that need to be backed up.
 @param force If YES, the photo check is forced regardless of internal states.
 */
- (void)checkPhotos:(BOOL)force;

/**
 Prepares the tool by initializing necessary data structures for the backup process.
 */
- (void)prepareForBackup;

/**
 Resets the internal state of the tool, clearing cached data and stopping any ongoing operations.
 */
- (void)resetAll;

/**
 Returns the number of photos currently being synchronized.
 @return The number of photos in synchronization.
 */
- (NSUInteger)photosInSyncing;

/**
 Resets the list of uploaded photos.
 */
- (void)resetUploadedPhotos;

/**
 Clears the list of uploading videos.
 */
- (void)clearUploadingVideos;

/**
 Returns the number of photos currently being uploaded.
 @return The number of photos in the uploading array.
 */
- (NSUInteger)photosInUploadingArray;

@end
