#import "SeafUploadFileManager.h"
#import "SeafUploadFile.h"
#import "SeafUploadFileModel.h"
#import "Utils.h"
#import "Debug.h"

@implementation SeafUploadFileManager

- (void)validateFileWithPath:(NSString *)path completion:(void (^)(BOOL success, NSError *error))completion {
    if (!path) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"SeafUploadFileManager" 
                                               code:-1 
                                           userInfo:@{NSLocalizedDescriptionKey: @"Invalid file path"}];
            completion(NO, error);
        }
        return;
    }
    
    BOOL isDirectory = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];
    
    if (!exists || isDirectory) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"SeafUploadFileManager" 
                                               code:-2 
                                           userInfo:@{NSLocalizedDescriptionKey: @"File does not exist or is a directory"}];
            completion(NO, error);
        }
        return;
    }
    
    if (completion) {
        completion(YES, nil);
    }
}

- (void)cleanupFile:(SeafUploadFile *)file {
    if (!file.model.lpath) return;
    
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:file.model.lpath error:&error];
    if (error) {
        Warning("Failed to remove file %@: %@", file.model.lpath, error);
    }
}

- (void)removeFile:(NSString *)path {
    if (!path) return;
    
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    if (error) {
        Warning("Failed to remove file at path %@: %@", path, error);
    }
}

- (long long)fileSizeAtPath:(NSString *)path {
    if (!path) return 0;
    
    NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
    if (error) {
        Warning("Failed to get file size for %@: %@", path, error);
        return 0;
    }
    
    return [attributes fileSize];
}

- (BOOL)saveFileStatus:(SeafUploadFile *)file withOid:(NSString *)oid {
    if (!file || !oid) return NO;
    
    NSString *cacheDir = [self uploadCacheDirectory];
    if (![Utils checkMakeDir:cacheDir]) {
        return NO;
    }
    
    NSString *statusPath = [self statusPathForFile:file];
    NSDictionary *status = @{
        @"oid": oid,
//        @"mtime": @(file.model.mtime),
        @"size": @(file.model.filesize),
        @"uploaded": @(YES)
    };
    
    return [status writeToFile:statusPath atomically:YES];
}

#pragma mark - Helper Methods

- (NSString *)uploadCacheDirectory {
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [documentsPath stringByAppendingPathComponent:@"UploadCache"];
}

- (NSString *)statusPathForFile:(SeafUploadFile *)file {
    NSString *fileName = [file.model.lpath lastPathComponent];
    NSString *statusFileName = [NSString stringWithFormat:@"%@.status", fileName];
    return [[self uploadCacheDirectory] stringByAppendingPathComponent:statusFileName];
}

@end 
