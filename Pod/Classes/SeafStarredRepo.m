//
//  SeafStarredRepo.m
//  Seafile
//
//  Created by henry on 2024/8/16.
//

#import "SeafStarredRepo.h"
#import "Utils.h"
#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"

@implementation SeafStarredRepo

- (id)initWithConnection:(SeafConnection *)aConnection Info:(NSDictionary *)infoDict {
    NSNumber *isDirNum = [infoDict objectForKey:@"is_dir"];
    int isDir = [isDirNum intValue];
    NSNumber *repoEncryptedNum = [infoDict objectForKey:@"repo_encrypted"];
    int repoEncrypted = [repoEncryptedNum intValue];
    
    NSString *mtimeStr = [infoDict objectForKey:@"mtime"];
    int mtime = [Utils convertTimeStringToUTC:mtimeStr];
    
    NSNumber *isDeletedNum = [infoDict objectForKey:@"deleted"];
    BOOL isDeleted = [isDeletedNum intValue];
    
    return [self initWithConnection:aConnection isDir:isDir  mtime:mtime objName:[infoDict objectForKey:@"obj_name"] path:[infoDict objectForKey:@"path"] repoEncrypted:repoEncrypted repoId:[infoDict objectForKey:@"repo_id"] repoName:[infoDict objectForKey:@"repo_name"] deleted:isDeleted];
}

- (nonnull id)initWithConnection:(nonnull SeafConnection *)aConnection isDir:(int)isDir mtime:(long long)mtime objName:(id)objName path:(nonnull NSString *)aPath repoEncrypted:(int)encrypted repoId:(nonnull NSString *)repoId repoName:(NSString *)repoName deleted:(BOOL)isDeleted{
    NSString *aMime = @"text/directory-documents";
//    if ([aPerm.lowercaseString isEqualToString:@"r"]) {
//        aMime = @"text/directory-documents-readonly";
//    }
    if (encrypted) {
        aMime = @"text/directory-documents-encrypted";
    }
    if (self = [super initWithConnection:aConnection oid:nil repoId:repoId name:objName path:aPath mime:aMime]) {
        _isDir = isDir;
        self.mtime = mtime;
        self.repoName = repoName;
        self.encrypted = encrypted;
        self.isDeleted = isDeleted;
    }
    return self;
}

- (NSString *)detailText
{
    if (self.mtime) {
        return [SeafDateFormatter stringFromLongLong:self.mtime];
    }
    return @"";
}

@end
