//
//  SeafFileModel.m
//  Seafile
//
//  Created by henry on 2025/1/22.
//

#import "SeafFileModel.h"
#import "FileMimeType.h"
#import "Utils.h"

@implementation SeafFileModel

- (instancetype)initWithOid:(NSString *)oid
                     repoId:(NSString *)repoId
                       name:(NSString *)name
                       path:(NSString *)path
                      mtime:(long long)mtime
                       size:(unsigned long long)size
                 connection:(SeafConnection *)conn
{
    // Use the designated initializer of the superclass SeafBaseModel, and calculate the mime directly through FileMimeType
    self = [super initWithOid:oid
                       repoId:repoId
                         name:name
                         path:path
                         mime:[FileMimeType mimeType:name]];
    if (self) {
        _mtime    = mtime;
        _filesize = size;
        _conn     = conn;
        _retryable = YES;
        _retryCount = 0;
    }
    return self;
}

#pragma mark - Custom Methods

- (NSString *)uniqueKey {
    NSString *normalizedPath = self.path ?: @"";
    if ([normalizedPath hasPrefix:@"/"]) {
        normalizedPath = [normalizedPath substringFromIndex:1];
    }
    // Here we assume conn.accountIdentifier exists, handle compatibility if not
    return [NSString stringWithFormat:@"%@/%@/%@", self.conn.accountIdentifier ?: @"",
                                          self.repoId ?: @"",
                                          normalizedPath];
}

- (BOOL)isImageFile {
    return [Utils isImageFile:self.name];
}

- (BOOL)isVideoFile {
    return [Utils isVideoFile:self.name];
}

- (BOOL)isEditable {
    // Simple example: check if MIME starts with "text/"
    return [self.mime hasPrefix:@"text/"];
}

- (NSDictionary *)toDictionary {
    return @{
        @"id": self.oid ?: @"",
        @"repoid": self.repoId ?: @"",
        @"path": self.path ?: @"",
        @"name": self.name ?: @"",
        @"mtime": @(self.mtime),
        @"size": @(self.filesize),
        @"mime": self.mime ?: @""
    };
}

@end
