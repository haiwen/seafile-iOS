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
    // 使用父类 SeafBaseModel 的指定初始化方法，将 mime 直接通过 FileMimeType 计算得到
    self = [super initWithOid:oid
                       repoId:repoId
                         name:name
                         path:path
                         mime:[FileMimeType mimeType:name]];
    if (self) {
        _mtime    = mtime;
        _filesize = size;
        _conn     = conn;
    }
    return self;
}

#pragma mark - 自定义方法

- (NSString *)uniqueKey {
    NSString *normalizedPath = self.path ?: @"";
    if ([normalizedPath hasPrefix:@"/"]) {
        normalizedPath = [normalizedPath substringFromIndex:1];
    }
    // 这里假设 conn.accountIdentifier 存在，如无则自行兼容处理
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
    // 简单示例：判断 MIME 是否以 "text/" 开头
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
