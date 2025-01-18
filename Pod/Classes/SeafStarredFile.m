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
#import "SeafRepos.h"


@implementation SeafStarredFile

- (id)initWithConnection:(SeafConnection *)aConnection Info:(NSDictionary *)infoDict {
    NSNumber *isDirNum = [infoDict objectForKey:@"is_dir"];
    int isDir = [isDirNum intValue];
    NSNumber *repoEncryptedNum = [infoDict objectForKey:@"repo_encrypted"];
    int repoEncrypted = [repoEncryptedNum intValue];
    
    NSString *mtimeStr = [infoDict objectForKey:@"mtime"];
    int mtime = [Utils convertTimeStringToUTC:mtimeStr];
    
    NSNumber *isDeletedNum = [infoDict objectForKey:@"deleted"];
    BOOL isDeleted = [isDeletedNum intValue];
    
    return [self initWithConnection:aConnection repo:[infoDict objectForKey:@"repo_id"] path:[infoDict objectForKey:@"path"] mtime:mtime objName:[infoDict objectForKey:@"obj_name"] isDir:isDir repoEncrypted:repoEncrypted thumbnail:[infoDict objectForKey:@"encoded_thumbnail_src"] repoName:[infoDict objectForKey:@"repo_name"] deleted:isDeleted];
}


- (id)initWithConnection:(SeafConnection *)aConnection
                    repo:(NSString *)aRepo
                    path:(NSString *)aPath
                   mtime:(long long)mtime
                 objName:(NSString *)objName
                   isDir:(int)isDir
           repoEncrypted:(int)repoEncrypted
               thumbnail:(NSString *)thumbnail
                repoName:(NSString *)repoName
                 deleted:(BOOL)isDeleted
{
    NSString *name = aPath.lastPathComponent;

    if (self = [super initWithConnection:aConnection oid:nil repoId:aRepo name:objName path:aPath mtime:mtime size:0 ]) {
        
        _isDir = isDir;
        self.encrypted = repoEncrypted;
        self.mtime = mtime;
        self.thumbnailURLStr = thumbnail;
        self.repoName = repoName;
        self.isDeleted = isDeleted;
    }
    return self;
}

- (NSString *)key
{
    return [NSString stringWithFormat:@"%@%@", self.repoId, self.path];
}

- (void)updateWithEntry:(SeafBase *)entry
{
    self.filesize = ((SeafStarredFile *)entry).filesize;
    self.mtime = ((SeafStarredFile *)entry).mtime;
    [self loadCache];
}

@end
