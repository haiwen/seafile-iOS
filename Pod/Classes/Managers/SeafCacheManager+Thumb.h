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

@end

NS_ASSUME_NONNULL_END
