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

// 预览相关
- (NSURL *)getPreviewItemURL;
- (NSString *)getPreviewItemTitle;

// 导出相关
- (NSURL *)getExportItemURLWithSeafFile:(SeafFile *)sFile oldExportURL:(NSURL *)oURL;
// 清理
- (void)cleanupPreviewFile;

- (NSURL *)getPreviewURL;

- (NSURL *)getPreviewItemURLWithSeafFile:(SeafFile *)sFile
                           oldPreviewURL:(NSURL *)oldPreviewURL;
@end
