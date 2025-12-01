#import "SeafBaseModel.h"
#import <Photos/Photos.h>

@interface SeafUploadFileModel : SeafBaseModel

// Upload status related
@property (nonatomic) BOOL uploading;
@property (nonatomic) BOOL uploaded;
@property (nonatomic) BOOL overwrite;
@property (nonatomic) long long lastFinishTimestamp;
@property (nonatomic) BOOL retryable;
@property (nonatomic) NSInteger retryCount;

// File attributes
@property (nonatomic, copy) NSString *lpath;      // Local path
@property (nonatomic) long long filesize;
@property (nonatomic) BOOL uploadFileAutoSync;
@property (nonatomic) BOOL starred;
@property (nonatomic) BOOL shouldShowUploadFailure;

// Resource related
@property (nonatomic, strong) PHAsset *asset;
@property (nonatomic, strong) NSURL *assetURL;
@property (nonatomic, copy) NSString *assetIdentifier;

// Live Photo / Motion Photo support
@property (nonatomic, assign) BOOL isLivePhoto;

// File editing related
@property (nonatomic, copy) NSString *editedFileRepoId;
@property (nonatomic, copy) NSString *editedFilePath;
@property (nonatomic, copy) NSString *editedFileOid;
@property (nonatomic) BOOL isEditedFile;

// Initialization methods
- (instancetype)initWithPath:(NSString *)path;
- (void)setAsset:(PHAsset *)asset url:(NSURL *)url identifier:(NSString *)identifier;

@end 
