//
//  SeafStarredFile.m
//  seafile
//
//  Created by Wang Wei on 11/4/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafStarredFile.h"
#import "SeafConnection.h"
#import "FileMimeType.h"
#import "Debug.h"


@implementation SeafStarredFile
@synthesize starDelegate = _starDelegate;
@synthesize org = _org;

- (id)initWithConnection:(SeafConnection *)aConnection
                    repo:(NSString *)aRepo
                    path:(NSString *)aPath
                   mtime:(long long)mtime
                    size:(long long)size
                     org:(int)org
                     oid:(NSString *)anId
{
    NSString *name = aPath.lastPathComponent;
    if (self = [super initWithConnection:aConnection oid:anId repoId:aRepo name:name path:aPath mtime:mtime size:size ]) {
        _org = org;
    }
    return self;
}

- (void)setStarred:(BOOL)starred
{
    [connection setStarred:starred repo:self.repoId path:self.path];
    [_starDelegate fileStateChanged:starred file:self];
}

- (NSString *)key
{
    return [NSString stringWithFormat:@"%@%@", self.repoId, self.path];
}

- (void)updateWithEntry:(SeafBase *)entry
{
    _filesize = ((SeafStarredFile *)entry).filesize;
    _mtime = ((SeafStarredFile *)entry).mtime;
    [self loadCache];
}

@end
