//
//  SeafResumableUploadRecord.m
//  Seafile
//

#import "SeafResumableUploadRecord.h"
#import <CommonCrypto/CommonDigest.h>

@implementation SeafProbeWindow

+ (instancetype)windowWithOffset:(long long)offset length:(NSUInteger)length sha1:(NSString *)sha1
{
    SeafProbeWindow *w = [self new];
    w->_offset = offset;
    w->_length = length;
    w->_sha1 = [sha1 copy];
    return w;
}

+ (instancetype)windowWithDictionary:(id)dict
{
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    id offset = dict[@"offset"], length = dict[@"length"], sha1 = dict[@"sha1"];
    if (![offset isKindOfClass:[NSNumber class]] || ![length isKindOfClass:[NSNumber class]]
        || ![sha1 isKindOfClass:[NSString class]] || [offset longLongValue] < 0 || [length longLongValue] <= 0
        || [(NSString *)sha1 length] != CC_SHA1_DIGEST_LENGTH * 2) {
        return nil;
    }
    return [self windowWithOffset:[offset longLongValue] length:(NSUInteger)[length unsignedLongLongValue] sha1:sha1];
}

- (NSDictionary *)dictionaryRepresentation
{
    return @{@"offset": @(self.offset), @"length": @(self.length), @"sha1": self.sha1 ?: @""};
}

- (BOOL)matchesData:(NSData *)data
{
    if (data.length != self.length) return NO;
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return [hex caseInsensitiveCompare:self.sha1] == NSOrderedSame;
}

- (BOOL)isEqual:(id)other
{
    if (![other isKindOfClass:[SeafProbeWindow class]]) return NO;
    SeafProbeWindow *w = other;
    return w.offset == self.offset && w.length == self.length && [w.sha1 isEqualToString:self.sha1];
}

- (NSUInteger)hash
{
    return (NSUInteger)self.offset ^ self.length ^ self.sha1.hash;
}

@end

@implementation SeafResumableUploadRecord

- (instancetype)init
{
    if (self = [super init]) {
        _attemptId = [NSUUID UUID].UUIDString;
        _taskId = @"";
        _account = @"";
        _repoId = @"";
        _parentDir = @"/";
        _targetName = @"";
        _stagingName = @"";
        _chunkSize = SeafResumableChunkSize;
        _chunkHashes = @[];
        _state = SeafResumableStateUploading;
    }
    return self;
}

+ (NSString *)targetKeyForAccount:(NSString *)account repoId:(NSString *)repoId
                        parentDir:(NSString *)parentDir targetName:(NSString *)targetName
{
    return [NSString stringWithFormat:@"%@|%@|%@|%@", account, repoId, parentDir, targetName];
}

- (NSString *)targetKey
{
    return [SeafResumableUploadRecord targetKeyForAccount:self.account repoId:self.repoId
                                                parentDir:self.parentDir targetName:self.targetName];
}

- (NSString *)stagingPath
{
    NSString *name = self.committedName.length > 0 ? self.committedName : self.stagingName;
    return [self.parentDir stringByAppendingPathComponent:name];
}

- (BOOL)isActive
{
    return self.state == SeafResumableStateUploading
        || self.state == SeafResumableStateFinalPending
        || self.state == SeafResumableStateCommitted
        || self.state == SeafResumableStateRenamePending;
}

- (id)copyWithZone:(NSZone *)zone
{
    SeafResumableUploadRecord *r = [[SeafResumableUploadRecord allocWithZone:zone] init];
    r.attemptId = self.attemptId;
    r.taskId = self.taskId;
    r.account = self.account;
    r.repoId = self.repoId;
    r.parentDir = self.parentDir;
    r.targetName = self.targetName;
    r.stagingName = self.stagingName;
    r.overwrite = self.overwrite;
    r.fileSize = self.fileSize;
    r.lastModify = self.lastModify;
    r.fileIdentity = self.fileIdentity;
    r.chunkSize = self.chunkSize;
    r.chunkHashes = self.chunkHashes;
    r.confirmedOffset = self.confirmedOffset;
    r.inflightEnd = self.inflightEnd;
    r.inflightHash = self.inflightHash;
    r.state = self.state;
    r.finalSentAt = self.finalSentAt;
    r.committedName = self.committedName;
    r.oid = self.oid;
    r.renameSnapshot = self.renameSnapshot;
    r.finalName = self.finalName;
    r.stagingCommitted = self.stagingCommitted;
    r.verified = self.verified;
    r.entry = self.entry;
    r.probeWindows = self.probeWindows;
    r.runToken = self.runToken;
    r.heartbeatAt = self.heartbeatAt;
    r.reason = self.reason;
    r.createdAt = self.createdAt;
    r.updatedAt = self.updatedAt;
    return r;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<attempt %@ task=%@ target=%@ staging=%@ state=%ld confirmed=%lld/%lld>",
            self.attemptId, self.taskId, self.targetKey, self.stagingName, (long)self.state,
            self.confirmedOffset, self.fileSize];
}

@end
