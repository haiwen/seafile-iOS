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

@interface SeafFilePreviewHandler ()
@property (nonatomic, strong) SeafFileModel *fileModel;
@property (nonatomic, strong) NSURL *previewItemURL;   // Used by getPreviewItemURL
@property (nonatomic, strong) NSURL *exportItemURL;    // Used by getExportItemURLWithSeafFile
@end

@implementation SeafFilePreviewHandler

- (instancetype)initWithFile:(SeafFileModel *)file {
    self = [super init];
    if (self) {
        _fileModel = file;
    }
    return self;
}

#pragma mark - Basic Methods

/// Used to get the QLPreviewItemTitle of the current file
- (NSString *)getPreviewItemTitle {
    return self.fileModel.name;
}

/// Returns the old previewItemURL (if it exists and the file is still there), otherwise creates/uses localPath
- (NSURL *)getPreviewItemURL {
    if (self.previewItemURL
        && [[NSFileManager defaultManager] fileExistsAtPath:self.previewItemURL.path]) {
        return self.previewItemURL;
    }
    
    // Returns a default local file path based on fileModel.localPath
    if (self.fileModel.localPath) {
        self.previewItemURL = [NSURL fileURLWithPath:self.fileModel.localPath isDirectory:NO];
    }
    return self.previewItemURL;
}

- (NSURL *)getExportURL {
    // Simple handling here, can also be done with exportDir in SeafStorage
    NSString *exportPath = [@"todo" stringByAppendingPathComponent:self.fileModel.name];
    [[NSFileManager defaultManager] copyItemAtPath:self.fileModel.localPath
                                            toPath:exportPath
                                             error:nil];
    return [NSURL fileURLWithPath:exportPath];
}

- (void)cleanupPreviewFile {
    if (self.previewItemURL) {
        [[NSFileManager defaultManager] removeItemAtURL:self.previewItemURL error:nil];
    }
}

#pragma mark - Methods corresponding to the original SeafFile previewItemURL logic

/// Merges the logic related to previewItemURL in SeafFile into this
- (NSURL *)getPreviewItemURLWithSeafFile:(SeafFile *)sFile
                           oldPreviewURL:(NSURL *)oldPreviewURL
{
    // 1. If oldPreviewURL exists and the file is still there, return it directly
    if (oldPreviewURL && [Utils fileExistsAtPath:oldPreviewURL.path]) {
        return oldPreviewURL;
    }
    
    // 2. First get the exported local URL (similar to sFile.exportURL)
    NSURL *exportURL = [self getExportItemURLWithSeafFile:sFile oldExportURL:nil];
    if (!exportURL) {
        // If not yet downloaded or other reasons prevent getting the export file, return nil
        return nil;
    }

    // 3. Decide whether to use exportURL directly based on mime, or jump to markdown/seafile/html, etc.
    NSString *mime = [FileMimeType mimeType:sFile.name];
    if (![mime hasPrefix:@"text"]) {
        // Non-text
        return exportURL;
    } else if ([mime hasSuffix:@"markdown"]) {
        return [self markdownPreviewURL];
    } else if ([mime hasSuffix:@"seafile"]) {
        return [self seafPreviewURL];
    }
    
    // 4. For plain text, try transcoding (UTF-8 BOM processing, etc.), and place it in a temporary directory
    NSString *src = sFile.mpath ?: [SeafStorage.sharedObject documentPath:sFile.ooid];
    NSString *tmpdir = [SeafStorage uniqueDirUnder:SeafStorage.sharedObject.tempDir];
    if (![Utils checkMakeDir:tmpdir]) {
        // If creating a temporary directory fails, use exportURL directly
        return exportURL;
    }
    NSString *dst = [tmpdir stringByAppendingPathComponent:sFile.name];
    
    @synchronized (sFile) {
        if ([Utils fileExistsAtPath:dst] ||
            [Utils tryTransformEncoding:dst fromFile:src]) {
            return [NSURL fileURLWithPath:dst isDirectory:NO];
        }
    }
    
    return exportURL;
}

#pragma mark - Export Logic

/// Combines the -exportURL logic from the original SeafFile.m
- (NSURL *)getExportItemURLWithSeafFile:(SeafFile *)sFile oldExportURL:(NSURL *)oURL
{
    // If the old exportURL is still there and exists, return it directly
    _exportItemURL = oURL;
    if (_exportItemURL && [Utils fileExistsAtPath:_exportItemURL.path]) {
        return _exportItemURL;
    }
    
    // If there is a local editing file path, return it directly
    if (sFile.mpath) {
        _exportItemURL = [NSURL fileURLWithPath:sFile.mpath isDirectory:NO];
        return _exportItemURL;
    }
    
    // If not yet downloaded (cache not present), return nil
    if (![[SeafCacheManager sharedManager] fileHasCache:sFile]) {
        return nil;
    }
    
    // Otherwise, try to link or copy from documentPath to a temporary directory, then return
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
            _exportItemURL = [NSURL fileURLWithPath:tempFileName isDirectory:NO];
        } else {
            Warning("Copy file to exportURL failed.\n");
            sFile.ooid = nil;
            _exportItemURL = nil;
        }
    }
    return _exportItemURL;
}

#pragma mark - Private Methods: Local HTML file paths for markdown/seafile

- (NSURL *)markdownPreviewURL {
    return [NSURL fileURLWithPath:[SeafileBundle() pathForResource:@"htmls/view_markdown" ofType:@"html"] isDirectory:NO];
}

- (NSURL *)seafPreviewURL {
    return [NSURL fileURLWithPath:[SeafileBundle() pathForResource:@"htmls/view_seaf" ofType:@"html"] isDirectory:NO];
}

@end
