#import "SeafUploadFileModel.h"
#import "Utils.h"

@implementation SeafUploadFileModel

#pragma mark - Initialization

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _lpath = path;
        _retryable = YES;
        _retryCount = 0;
        _uploading = NO;
        _uploadFileAutoSync = NO;
        _starred = NO;
        _uploaded = NO;
        _overwrite = NO;
        _shouldShowUploadFailure = YES;
        
        // 初始化文件大小
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
    _assetIdentifier = identifier;
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

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    SeafUploadFileModel *copy = [[SeafUploadFileModel alloc] initWithPath:self.lpath];
    copy.filesize = self.filesize;
    copy.lastFinishTimestamp = self.lastFinishTimestamp;
    copy.retryable = self.retryable;
    copy.retryCount = self.retryCount;
    copy.uploading = self.uploading;
    copy.uploadFileAutoSync = self.uploadFileAutoSync;
    copy.starred = self.starred;
    copy.uploaded = self.uploaded;
    copy.overwrite = self.overwrite;
    copy.shouldShowUploadFailure = self.shouldShowUploadFailure;
    
    // Copy asset related properties
    copy.asset = self.asset;
    copy.assetURL = self.assetURL;
    copy.assetIdentifier = self.assetIdentifier;
    
    // Copy edited file properties
    copy.isEditedFile = self.isEditedFile;
    copy.editedFileRepoId = self.editedFileRepoId;
    copy.editedFilePath = self.editedFilePath;
    copy.editedFileOid = self.editedFileOid;
    
    return copy;
}

#pragma mark - Debug Description

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p> path: %@, size: %lld, uploading: %d, uploaded: %d, retryCount: %ld", 
            NSStringFromClass([self class]), 
            self, 
            self.lpath, 
            self.filesize, 
            self.uploading,
            self.uploaded,
            (long)self.retryCount];
}

@end 