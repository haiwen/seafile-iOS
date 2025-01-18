#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

@class SeafUploadFile;

@interface SeafAssetManager : NSObject

- (void)setAsset:(PHAsset *)asset url:(NSURL *)url forFile:(SeafUploadFile *)file;
- (void)checkAssetWithFile:(SeafUploadFile *)file completion:(void (^)(BOOL success, NSError *error))completion;
- (void)getImageDataForAsset:(SeafUploadFile *)file completion:(void (^)(BOOL success, NSError *error))completion;
- (void)getVideoForAsset:(SeafUploadFile *)file completion:(void (^)(BOOL success, NSError *error))completion;
- (BOOL)convertHEICToJPEG:(NSURL *)sourceURL destination:(NSURL *)destinationURL;

@end 