#import <Foundation/Foundation.h>

@class SeafUploadFile;

@interface SeafUploadStateManager : NSObject

- (void)cancelUpload:(SeafUploadFile *)file;
- (void)finishUpload:(SeafUploadFile *)file withResult:(BOOL)result oid:(NSString *)oid error:(NSError *)error;
- (void)saveUploadFileToStorage:(SeafUploadFile *)file;
- (void)updateUploadProgress:(SeafUploadFile *)file progress:(float)progress;

@end 