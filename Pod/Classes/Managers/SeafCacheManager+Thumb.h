//
//  SeafCacheManager+Thumb.h
//  Seafile
//
//  Created by henry on 2025/1/24.
//

#import "SeafCacheManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface SeafCacheManager (Thumb)

/// Returns the icon for a SeafFile (if it's an image/video, it first tries to get it from the thumbnail cache, if not available, it initiates generation/download logic)
- (UIImage *_Nullable)iconForFile:(SeafFile *)file;

/// Generate or download a thumbnail (if it already exists, read it directly), and callback upon success
- (void)generateThumbForFile:(SeafFile *)file completion:(void (^)(BOOL success, UIImage *_Nullable thumb))completion;

/// Cancel thumbnail download or generation
- (void)cancelThumbForFile:(SeafFile *)file;

// Determine if the file is an image/video file based on the file
- (BOOL)isImageFile:(SeafFile *)file;
- (BOOL)isVideoFile:(SeafFile *)file;

- (UIImage *)thumbForFile:(SeafFile *)file;

- (NSString *)thumbPath:(NSString *)objId sFile:(SeafFile *)sFile;

- (void)saveThumbFromEncrypetedFile:(SeafFile *)seafFile;

/// Remember a failed thumbnail fetch so we do not spin-retry on every cell refresh.
/// Record a permanent failure (server 4xx: this file version can't be thumbnailed).
- (void)markThumbDownloadPermanentlyFailedForFile:(SeafFile *)file;
/// Record a transient failure (server 5xx / non-image body) for backed-off, capped retry.
- (void)markThumbDownloadTransientlyFailedForFile:(SeafFile *)file;
/// Clear any failure record (e.g. after a successful download).
- (void)clearThumbDownloadFailedForFile:(SeafFile *)file;
/// Whether a thumbnail download should be skipped now (permanent / retry cap reached / within backoff).
- (BOOL)shouldSkipThumbDownloadForFile:(SeafFile *)file;

@end

NS_ASSUME_NONNULL_END
