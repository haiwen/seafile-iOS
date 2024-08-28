//
//  SeafStarredDir.m
//  Seafile
//
//  Created by henry on 2024/8/18.
//

#import "SeafStarredDir.h"
#import "SeafDateFormatter.h"
#import "Utils.h"
#import "Debug.h"

@implementation SeafStarredDir

- (id)initWithConnection:(SeafConnection *)aConnection Info:(NSDictionary *)infoDict {
    // if infoDict not nil
    if (infoDict == nil) {
        Debug(@"Error: infoDict is nil");
        return nil;
    }
    
    NSNumber *isDirNum = [infoDict objectForKey:@"is_dir"];
    int isDir = [isDirNum intValue];
    NSNumber *repoEncryptedNum = [infoDict objectForKey:@"repo_encrypted"];
    int repoEncrypted = [repoEncryptedNum intValue];
    
    NSString *mtimeStr = [infoDict objectForKey:@"mtime"];
    int mtime = [Utils convertTimeStringToUTC:mtimeStr];
    
    NSNumber *isDeletedNum = [infoDict objectForKey:@"deleted"];
    BOOL isDeleted = [isDeletedNum intValue];
    
    return [self initWithConnection:aConnection oid:nil repoId:[infoDict objectForKey:@"repo_id"] perm:nil name:[infoDict objectForKey:@"obj_name"] path:[infoDict objectForKey:@"path"] isDir:isDir mtime:mtime repoEncrypted:repoEncrypted repoName:[infoDict objectForKey:@"repo_name"] deleted:isDeleted];
}

- (id)initWithConnection:(SeafConnection *)connection
                     oid:(NSString *)oid
                  repoId:(NSString *)repoId
                    perm:(NSString *)perm
                    name:(NSString *)name
                    path:(NSString *)path
                   isDir:(int)isDir
                   mtime:(long long)mtime
           repoEncrypted:(int)repoEncrypted
                 repoName:(NSString *)repoName
                 deleted:(BOOL)isDeleted
{
    self = [super initWithConnection:connection oid:oid repoId:repoId perm:perm name:name path:path];
    if (self) {
        _isDir = isDir;
        _mtime = mtime;
        self.encrypted = repoEncrypted;
        self.repoName = repoName;
        self.isDeleted = isDeleted;
    }
    return self;
}

- (NSString *)detailText
{
    NSString *detailStr = self.repoName;
    if (self.mtime) {
        NSString *timeStr = [SeafDateFormatter stringFromLongLong:self.mtime];
        detailStr = [detailStr stringByAppendingFormat:@" · %@", timeStr];
        return detailStr;
    }
    return detailStr;
}

@end
