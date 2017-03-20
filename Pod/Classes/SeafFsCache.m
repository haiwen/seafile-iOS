//
//  SeafFsCache.m
//  Pods
//
//  Created by Wei W on 4/8/17.
//
//

#import "SeafFsCache.h"
#import "Utils.h"
#import "Debug.h"


#define OBJECTS_DIR @"objects"
#define AVATARS_DIR @"avatars"
#define CERTS_DIR @"certs"
#define BLOCKS_DIR @"blocks"
#define UPLOADS_DIR @"uploads"
#define EDIT_DIR @"edit"
#define THUMB_DIR @"thumb"
#define TEMP_DIR @"temp"

@interface SeafFsCache()

@property (retain) NSString * cacheRootPath;
@property (retain) NSString * tempPath;

@end

@implementation SeafFsCache


+ (SeafFsCache *)sharedObject
{
    static SeafFsCache *object = nil;
    if (!object) {
        object = [[SeafFsCache alloc] init];
    }
    return object;
}

-(id)init
{
    if (self = [super init]) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        _cacheRootPath = [paths objectAtIndex:0];
    }
    return self;
}

- (void)registerRootPath:(NSString *)path
{
    _cacheRootPath = path;
    [Utils checkMakeDir:self.objectsDir];
    [Utils checkMakeDir:self.avatarsDir];
    [Utils checkMakeDir:self.certsDir];
    [Utils checkMakeDir:self.blocksDir];
    [Utils checkMakeDir:self.uploadsDir];
    [Utils checkMakeDir:self.editDir];
    [Utils checkMakeDir:self.thumbsDir];
    [Utils checkMakeDir:self.tempDir];
}

- (NSURL *)rootPathURL
{
    return [NSURL fileURLWithPath:_cacheRootPath];
}

- (NSString *)rootPath
{
    return _cacheRootPath;
}

- (NSString *)uploadsDir
{
    return [self.rootPath stringByAppendingPathComponent:UPLOADS_DIR];
}

- (NSString *)avatarsDir
{
    return [self.rootPath stringByAppendingPathComponent:AVATARS_DIR];
}
- (NSString *)certsDir
{
    return [self.rootPath stringByAppendingPathComponent:CERTS_DIR];
}
- (NSString *)editDir
{
    return [self.rootPath stringByAppendingPathComponent:EDIT_DIR];
}
- (NSString *)thumbsDir
{
    return [self.rootPath stringByAppendingPathComponent:THUMB_DIR];
}
- (NSString *)objectsDir
{
    return [self.rootPath stringByAppendingPathComponent:OBJECTS_DIR];
}

- (NSString *)blocksDir
{
    return [self.rootPath stringByAppendingPathComponent:BLOCKS_DIR];
}
- (NSString *)tempDir
{
    return [[self rootPath] stringByAppendingPathComponent:TEMP_DIR];
}

- (NSString *)documentPath:(NSString*)fileId
{
    return [self.objectsDir stringByAppendingPathComponent:fileId];
}

- (NSString *)blockPath:(NSString*)blkId
{
    return [self.blocksDir stringByAppendingPathComponent:blkId];
}

- (long long)cacheSize
{
    return [Utils folderSizeAtPath:self.rootPath];
}

- (void)clearCache
{
    Debug("clear local cache.");
    [Utils clearAllFiles:SeafFsCache.sharedObject.objectsDir];
    [Utils clearAllFiles:SeafFsCache.sharedObject.blocksDir];
    [Utils clearAllFiles:SeafFsCache.sharedObject.editDir];
    [Utils clearAllFiles:SeafFsCache.sharedObject.thumbsDir];
    [Utils clearAllFiles:SeafFsCache.sharedObject.tempDir];
}

+ (NSString *)uniqueDirUnder:(NSString *)dir identify:(NSString *)identify
{
    return [dir stringByAppendingPathComponent:identify];
}

+ (NSString *)uniqueDirUnder:(NSString *)dir
{
    return [SeafFsCache uniqueDirUnder:dir identify:[[NSUUID UUID] UUIDString]];
}

- (NSString *)uniqueUploadDir
{
    return [SeafFsCache uniqueDirUnder:self.uploadsDir identify:[[NSUUID UUID] UUIDString]];
}

@end
