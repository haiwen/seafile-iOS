#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

@interface SeafUploadFileModel : NSObject

@property (nonatomic, copy) NSString *lpath;
@property (nonatomic) long long filesize;
@property (nonatomic) long long lastFinishTimestamp;
@property (nonatomic) BOOL retryable;
@property (nonatomic) NSInteger retryCount;

@property (nonatomic) BOOL uploading;
@property (nonatomic) BOOL uploadFileAutoSync;
@property (nonatomic) BOOL starred;
@property (nonatomic) BOOL uploaded;
@property (nonatomic) BOOL overwrite;
@property (nonatomic) BOOL shouldShowUploadFailure;

@property (nonatomic, strong) PHAsset *asset;
@property (nonatomic, strong) NSURL *assetURL;
@property (nonatomic, copy) NSString *assetIdentifier;

@property (nonatomic, copy) NSString *editedFileRepoId;
@property (nonatomic, copy) NSString *editedFilePath;
@property (nonatomic, copy) NSString *editedFileOid;
@property (nonatomic) BOOL isEditedFile;

- (instancetype)initWithPath:(NSString *)path;

- (void)setAsset:(PHAsset *)asset url:(NSURL *)url identifier:(NSString *)identifier;

@end 
