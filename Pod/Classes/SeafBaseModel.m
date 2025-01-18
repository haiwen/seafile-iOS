//
//  SeafBaseModel.m
//  Seafile
//
//  Created by henry on 2025/1/23.
//

#import "SeafBaseModel.h"

@implementation SeafBaseModel

- (instancetype)initWithOid:(NSString *)oid
                     repoId:(NSString *)repoId
                       name:(NSString *)name
                       path:(NSString *)path
                       mime:(NSString *)mime
{
    self = [super init];
    if (self) {
        _oid = [oid copy];
        _repoId = [repoId copy];
        _name = [name copy];
        _path = [path copy];
        _mime = [mime copy];
    }
    return self;
}

@end
