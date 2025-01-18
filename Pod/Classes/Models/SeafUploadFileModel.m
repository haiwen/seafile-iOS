#import "SeafUploadFileModel.h"
#import "Utils.h"
#import "Debug.h"

@implementation SeafUploadFileModel

#pragma mark - Initialization

- (instancetype)initWithPath:(NSString *)path {
    NSString *name = [path lastPathComponent];
    
    self = [super initWithOid:nil
                      repoId:nil
                        name:name
                        path:nil
                        mime:nil];
    
    if (self) {
        _lpath = [path copy];
        _uploading = NO;
        _uploaded = NO;
        _uploadFileAutoSync = NO;
        _starred = NO;
        _overwrite = NO;
        _shouldShowUploadFailure = YES;
        _retryable = YES;
        _retryCount = 0;
        _lastFinishTimestamp = 0;
        _isEditedFile = NO;
        
        // Initialize file size
        [self updateFileSize];
    }
    return self;
}

#pragma mark - Property Accessors

- (void)setLpath:(NSString *)lpath {
    if (_lpath != lpath) {
        _lpath = [lpath copy];
        [self updateFileSize];
    }
}

- (long long)filesize {
    if (!_filesize || _filesize == 0) {
        [self updateFileSize];
    }
    return _filesize;
}

#pragma mark - File Operations

- (void)updateFileSize {
    if (_lpath) {
        _filesize = [Utils fileSizeAtPath1:_lpath];
    }
}

- (long long)mtime {
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.lpath]) {
        return [[NSDate date] timeIntervalSince1970];
    } else {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.lpath error:nil];
        return [[attributes fileModificationDate] timeIntervalSince1970];
    }
}

#pragma mark - Asset Management

- (void)setAsset:(PHAsset *)asset url:(NSURL *)url identifier:(NSString *)identifier {
    _asset = asset;
    _assetURL = url;
    _assetIdentifier = [identifier copy];
    
    // If the file name is empty, get it from the URL
    if (!self.name || [self.name isEqualToString:@""]) {
        self.name = [url lastPathComponent];
    }
    
    if (asset) {
        _starred = asset.isFavorite;
    }
}

#pragma mark - State Management

- (void)markAsUploading {
    _uploading = YES;
    _uploaded = NO;
}

- (void)markAsUploaded {
    _uploading = NO;
    _uploaded = YES;
}

- (void)resetUploadState {
    _uploading = NO;
    _uploaded = NO;
}

- (void)incrementRetryCount {
    _retryCount++;
}

- (void)resetRetryCount {
    _retryCount = 0;
}

#pragma mark - Edited File Management

- (void)setupAsEditedFile:(NSString *)repoId path:(NSString *)path oid:(NSString *)oid {
    _isEditedFile = YES;
    _editedFileRepoId = [repoId copy];
    _editedFilePath = [path copy];
    _editedFileOid = [oid copy];
}

- (void)clearEditedFileInfo {
    _isEditedFile = NO;
    _editedFileRepoId = nil;
    _editedFilePath = nil;
    _editedFileOid = nil;
}

#pragma mark - Debug Description

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p> name: %@, path: %@, lpath: %@, uploading: %d, uploaded: %d", 
            NSStringFromClass([self class]), 
            self, 
            self.name, 
            self.path, 
            self.lpath, 
            self.uploading, 
            self.uploaded];
}

@end
