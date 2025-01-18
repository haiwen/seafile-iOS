//
//  SeafFilePreviewHandler.m
//  AFNetworking
//
//  Created by henry on 2025/1/23.
//

#import "SeafFilePreviewHandler.h"
#import "SeafStorage.h"
#import "Utils.h"
#import "FileMimeType.h"
#import "Debug.h"
#import "SeafFile.h"

//static NSBundle* SeafileBundle(void) {
//    static NSBundle* bundle = nil;
//    static dispatch_once_t onceToken;
//    dispatch_once(&onceToken, ^{
//        NSString* mainBundlePath = [[NSBundle mainBundle] resourcePath];
//        NSString* frameworkBundlePath = [mainBundlePath stringByAppendingPathComponent:@"Seafile.bundle"];
//        bundle = [NSBundle bundleWithPath:frameworkBundlePath];
//        if (!bundle) {
//            bundle = [NSBundle mainBundle];
//        }
//    });
//    return bundle;
//}

@interface SeafFilePreviewHandler ()
@property (nonatomic, strong) SeafFileModel *fileModel;
@property (nonatomic, strong) NSURL *previewItemURL;   // 供 getPreviewItemURL 使用
@property (nonatomic, strong) NSURL *exportItemURL;    // 供 getExportItemURLWithSeafFile 使用
@end

@implementation SeafFilePreviewHandler

- (instancetype)initWithFile:(SeafFileModel *)file {
    self = [super init];
    if (self) {
        _fileModel = file;
        // 也可以在此根据 fileModel 初始化 _previewItemURL
        // 比如做一些默认的预览文件路径设置
    }
    return self;
}

#pragma mark - 基础方法

/// 用于获取当前文件的 QLPreviewItemTitle
- (NSString *)getPreviewItemTitle {
    return self.fileModel.name;
}

/// 返回旧的 previewItemURL（如果存在且文件还在），否则自行创建/使用 localPath
- (NSURL *)getPreviewItemURL {
    if (self.previewItemURL
        && [[NSFileManager defaultManager] fileExistsAtPath:self.previewItemURL.path]) {
        return self.previewItemURL;
    }
    
    // 根据 fileModel.localPath 返回一个默认的本地文件路径
    if (self.fileModel.localPath) {
        self.previewItemURL = [NSURL fileURLWithPath:self.fileModel.localPath];
    }
    return self.previewItemURL;
}

/// 仅演示如何获取 exportURL，必要时可在这里对文件做 copy、link 等操作
- (NSURL *)getExportURL {
    // 这里简单处理，也可以在 SeafStorage 中有 exportDir 来做
    NSString *exportPath = [@"todo" stringByAppendingPathComponent:self.fileModel.name];
    [[NSFileManager defaultManager] copyItemAtPath:self.fileModel.localPath
                                            toPath:exportPath
                                             error:nil];
    return [NSURL fileURLWithPath:exportPath];
}

/// 如果需要清理预览文件，比如临时转换后的 HTML/Text
- (void)cleanupPreviewFile {
    if (self.previewItemURL) {
        [[NSFileManager defaultManager] removeItemAtURL:self.previewItemURL error:nil];
    }
}

#pragma mark - 与原 SeafFile previewItemURL 逻辑对应的方法

/// 将 SeafFile 里 previewItemURL 相关的逻辑合并到这
- (NSURL *)getPreviewItemURLWithSeafFile:(SeafFile *)sFile
                           oldPreviewURL:(NSURL *)oldPreviewURL
{
    // 1. 如果 oldPreviewURL 存在且文件还在，就直接返回
    if (oldPreviewURL && [Utils fileExistsAtPath:oldPreviewURL.path]) {
        return oldPreviewURL;
    }
    
    // 2. 先获取导出的本地 URL（类似 sFile.exportURL）
    NSURL *exportURL = [self getExportItemURLWithSeafFile:sFile oldExportURL:nil];
    if (!exportURL) {
        // 如果还没有下载完或其它原因导致拿不到导出文件，则返回空
        return nil;
    }

    // 3. 根据 mime 决定是否直接用 exportURL，还是跳转到 markdown/seafile/html 等
    NSString *mime = [FileMimeType mimeType:sFile.name];
    if (![mime hasPrefix:@"text"]) {
        // 非文本
        return exportURL;
    } else if ([mime hasSuffix:@"markdown"]) {
        return [self markdownPreviewURL];
    } else if ([mime hasSuffix:@"seafile"]) {
        return [self seafPreviewURL];
    }
    
    // 4. 对普通文本，尝试转码（UTF-8 BOM处理等），并放在临时目录
    NSString *src = sFile.mpath ?: [SeafStorage.sharedObject documentPath:sFile.ooid];
    NSString *tmpdir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.tempDir];
    if (![Utils checkMakeDir:tmpdir]) {
        // 创建临时目录失败，就直接用 exportURL
        return exportURL;
    }
    NSString *dst = [tmpdir stringByAppendingPathComponent:sFile.name];
    
    @synchronized (sFile) {
        if ([Utils fileExistsAtPath:dst] ||
            [Utils tryTransformEncoding:dst fromFile:src]) {
            return [NSURL fileURLWithPath:dst];
        }
    }
    
    return exportURL;
}

#pragma mark - 导出逻辑

/// 结合原本 SeafFile.m 里的 -exportURL 逻辑
- (NSURL *)getExportItemURLWithSeafFile:(SeafFile *)sFile oldExportURL:(NSURL *)oURL
{
    // 如果旧的 exportURL 还在且存在，就直接返回
    _exportItemURL = oURL;
    if (_exportItemURL && [Utils fileExistsAtPath:_exportItemURL.path]) {
        return _exportItemURL;
    }
    
    // 如果本地有编辑中的文件路径，就直接返回
    if (sFile.mpath) {
        _exportItemURL = [NSURL fileURLWithPath:sFile.mpath];
        return _exportItemURL;
    }
    
    // 如果还没下载完成（cache 不在），就返回 nil
    if (![[SeafCacheManager sharedManager] fileHasCache:sFile]) {
        return nil;
    }
    
    // 否则尝试从 documentPath link 或 copy 到临时目录后，返回
    @synchronized (sFile) {
        NSString *tempDir = [SeafStorage.sharedObject.tempDir stringByAppendingPathComponent:sFile.ooid];
        if (![Utils checkMakeDir:tempDir]) {
            return nil;
        }
        NSString *tempFileName = [tempDir stringByAppendingPathComponent:sFile.name];
        Debug("File exists at %@, %d", tempFileName, [Utils fileExistsAtPath:tempFileName]);
        
        if ([Utils fileExistsAtPath:tempFileName] ||
            [Utils linkFileAtPath:[SeafStorage.sharedObject documentPath:sFile.ooid]
                               to:tempFileName
                            error:nil]) {
            _exportItemURL = [NSURL fileURLWithPath:tempFileName];
        } else {
            Warning("Copy file to exportURL failed.\n");
            sFile.ooid = nil;
            _exportItemURL = nil;
        }
    }
    return _exportItemURL;
}

#pragma mark - 私有方法：markdown/seafile 的本地 HTML 文件路径

- (NSURL *)markdownPreviewURL {
    return [NSURL fileURLWithPath:[SeafileBundle() pathForResource:@"htmls/view_markdown" ofType:@"html"]];
}

- (NSURL *)seafPreviewURL {
    return [NSURL fileURLWithPath:[SeafileBundle() pathForResource:@"htmls/view_seaf" ofType:@"html"]];
}

@end
