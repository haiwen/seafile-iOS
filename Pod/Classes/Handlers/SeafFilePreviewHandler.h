//
//  SeafFilePreviewHandler.h
//  AFNetworking
//
//  Created by henry on 2025/1/23.
//

#import <QuickLook/QuickLook.h>
#import "SeafFileModel.h"

@class SeafFile;
@interface SeafFilePreviewHandler : NSObject

@property (nonatomic, strong, readonly) SeafFileModel *fileModel;

- (instancetype)initWithFile:(SeafFileModel *)file;

// Preview related
- (NSURL *)getPreviewItemURL;
- (NSString *)getPreviewItemTitle;

// Export related
- (NSURL *)getExportItemURLWithSeafFile:(SeafFile *)sFile oldExportURL:(NSURL *)oURL;
// Cleanup
- (void)cleanupPreviewFile;

- (NSURL *)getPreviewURL;

- (NSURL *)getPreviewItemURLWithSeafFile:(SeafFile *)sFile
                           oldPreviewURL:(NSURL *)oldPreviewURL;
@end
