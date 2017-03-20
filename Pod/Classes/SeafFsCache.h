//
//  SeafFsCache.h
//  Pods
//
//  Created by Wei W on 4/8/17.
//
//

#import <Foundation/Foundation.h>

@interface SeafFsCache : NSObject

+ (SeafFsCache *)sharedObject;


// nil for default
- (void)registerRootPath:(NSString *)path;

- (NSString *)rootPath;

- (NSString *)tempDir;
- (NSString *)uploadsDir;
- (NSString *)avatarsDir;
- (NSString *)certsDir;
- (NSString *)editDir;
- (NSString *)thumbsDir;
- (NSString *)objectsDir;
- (NSString *)blocksDir;

- (NSString *)documentPath:(NSString*)fileId;
- (NSString *)blockPath:(NSString*)blkId;

- (NSString *)uniqueUploadDir;

- (void)clearCache;

+ (NSString *)uniqueDirUnder:(NSString *)dir;

- (long long)cacheSize;

@end
