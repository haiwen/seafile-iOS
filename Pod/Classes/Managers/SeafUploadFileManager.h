#import <Foundation/Foundation.h>

@class SeafUploadFile;

@interface SeafUploadFileManager : NSObject

- (void)cleanupFile:(SeafUploadFile *)file;
- (void)validateFileWithPath:(NSString *)path completion:(void (^)(BOOL success, NSError *error))completion;
- (BOOL)saveFileStatus:(SeafUploadFile *)file withOid:(NSString *)oid;
- (void)removeFile:(NSString *)path;
- (long long)fileSizeAtPath:(NSString *)path;

@end 