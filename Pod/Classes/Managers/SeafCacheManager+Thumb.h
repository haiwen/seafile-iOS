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

/// On-disk cache path for a file's thumbnail: `{oid}-256px`, or `{name}-{mtime}-256px`
/// when the oid is unknown (starred entries). The suffix is SEAF_THUMB_PIXEL_SIZE,
/// so a size change retires old files instead of serving them at the wrong size.
- (NSString *)thumbCachePathForFile:(SeafFile *)file;

- (void)saveThumbFromEncrypetedFile:(SeafFile *)seafFile;

/// Remember a failed thumbnail fetch so we do not spin-retry on every cell refresh.
/// Record a permanent failure (401/403/404/415 etc.: this file version can't be thumbnailed).
- (void)markThumbDownloadPermanentlyFailedForFile:(SeafFile *)file;
/// Record a counted transient failure (400, 500 and other 5xx, non-image body):
/// short backoff, and the file is given up for the session after a few of them.
- (void)markThumbDownloadTransientlyFailedForFile:(SeafFile *)file;
/// Record a busy signal (408/429/502/503/504, request timeout): short backoff only,
/// never counted, because the server is still working and a later request succeeds.
- (void)markThumbDownloadBusyForFile:(SeafFile *)file;
/// Clear any failure record (e.g. after a successful download).
- (void)clearThumbDownloadFailedForFile:(SeafFile *)file;
/// Whether a thumbnail download should be skipped now (permanent / retry cap reached / within backoff).
- (BOOL)shouldSkipThumbDownloadForFile:(SeafFile *)file;

@end

NS_ASSUME_NONNULL_END
