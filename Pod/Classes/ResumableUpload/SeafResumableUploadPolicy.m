//
//  SeafResumableUploadPolicy.m
//  Seafile
//

#import "SeafResumableUploadPolicy.h"
#import <Security/Security.h>

static NSString * const kAFResponseDataKey = @"com.alamofire.serialization.response.error.data";

@implementation SeafResumableProbeResult
+ (instancetype)resultWithKind:(SeafResumableProbeKind)kind uploadedBytes:(long long)bytes
{
    SeafResumableProbeResult *r = [SeafResumableProbeResult new];
    r->_kind = kind;
    r->_uploadedBytes = bytes;
    return r;
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<probe kind=%ld bytes=%lld>", (long)_kind, _uploadedBytes];
}
@end

@implementation SeafResumableChunkResult
+ (instancetype)resultWithOutcome:(SeafResumableChunkOutcome)outcome status:(NSInteger)status
{
    return [self resultWithOutcome:outcome status:status name:nil fileId:nil size:-1];
}
+ (instancetype)resultWithOutcome:(SeafResumableChunkOutcome)outcome status:(NSInteger)status
                             name:(NSString *)name fileId:(NSString *)fileId size:(long long)size
{
    SeafResumableChunkResult *r = [SeafResumableChunkResult new];
    r->_outcome = outcome;
    r->_status = status;
    r->_committedName = [name copy];
    r->_committedId = [fileId copy];
    r->_committedSize = size;
    return r;
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<chunk outcome=%ld status=%ld name=%@ size=%lld>",
            (long)_outcome, (long)_status, _committedName, _committedSize];
}
@end

@implementation SeafResumableUploadPolicy

#pragma mark - Eligibility and naming

+ (BOOL)shouldSegmentFileOfSize:(long long)size
{
    return SeafResumableUploadEnabled && size > SeafResumableMinFileSize;
}

+ (NSString *)stagingNameForTargetName:(NSString *)targetName randomHex:(NSString *)randomHex
{
    NSString *ext = targetName.pathExtension;
    BOOL keepExt = ext.length > 0 && ext.length <= 16;
    if (keepExt) {
        NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
        for (NSUInteger i = 0; i < ext.length; i++) {
            unichar c = [ext characterAtIndex:i];
            if (c > 127 || ![allowed characterIsMember:c]) { keepExt = NO; break; }
        }
    }
    NSString *base = [SeafResumableStagingPrefix stringByAppendingString:randomHex];
    return keepExt ? [base stringByAppendingPathExtension:ext] : base;
}

+ (NSString *)stagingNameForTargetName:(NSString *)targetName
{
    uint8_t bytes[8];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) {
        arc4random_buf(bytes, sizeof(bytes));
    }
    NSMutableString *hex = [NSMutableString stringWithCapacity:16];
    for (size_t i = 0; i < sizeof(bytes); i++) [hex appendFormat:@"%02x", bytes[i]];
    return [self stagingNameForTargetName:targetName randomHex:hex];
}

+ (BOOL)isStagingName:(NSString *)name
{
    return [name hasPrefix:SeafResumableStagingPrefix];
}

+ (NSString *)normalizedName:(NSString *)name
{
    return name.precomposedStringWithCanonicalMapping ?: @"";
}

+ (NSString *)lastModifyStringForDate:(NSDate *)date
{
    if (!date) return nil;
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    });
    @synchronized (formatter) {
        return [formatter stringFromDate:date];
    }
}

+ (long long)segmentCountForFileSize:(long long)fileSize chunkSize:(long long)chunkSize
{
    if (fileSize <= 0 || chunkSize <= 0) return 0;
    return (fileSize + chunkSize - 1) / chunkSize;
}

+ (long long)segmentEndForStart:(long long)start fileSize:(long long)fileSize chunkSize:(long long)chunkSize
{
    return MIN(start + chunkSize, fileSize) - 1;
}

#pragma mark - Query decision table

+ (BOOL)acceptsByteRanges:(NSString *)headerValue
{
    if (headerValue.length == 0) return NO;
    for (NSString *token in [headerValue componentsSeparatedByString:@","]) {
        NSString *t = [token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([t caseInsensitiveCompare:@"bytes"] == NSOrderedSame) return YES;
    }
    return NO;
}

+ (SeafResumableProbeResult *)interpretProbeWithStatus:(NSInteger)status
                                          acceptRanges:(NSString *)acceptRanges
                                                  body:(id)body
                                                 error:(NSError *)error
{
    if ([self isCancellationError:error]) {
        return [SeafResumableProbeResult resultWithKind:SeafResumableProbeCancelled uploadedBytes:0];
    }
    // No HTTP answer at all, or a server-side failure: try again later.
    if (status == 0 || status >= 500) {
        return [SeafResumableProbeResult resultWithKind:SeafResumableProbeTransient uploadedBytes:0];
    }
    if (status == 404) {
        return [SeafResumableProbeResult resultWithKind:SeafResumableProbeTerminal uploadedBytes:0];
    }
    if (status < 200 || status >= 300) {
        return [SeafResumableProbeResult resultWithKind:SeafResumableProbeInvalid uploadedBytes:0];
    }
    if (![body isKindOfClass:[NSDictionary class]]) {
        return [SeafResumableProbeResult resultWithKind:SeafResumableProbeInvalid uploadedBytes:0];
    }
    id value = ((NSDictionary *)body)[@"uploadedBytes"];
    if (![value isKindOfClass:[NSNumber class]] || CFNumberIsFloatType((__bridge CFNumberRef)value)) {
        return [SeafResumableProbeResult resultWithKind:SeafResumableProbeInvalid uploadedBytes:0];
    }
    long long bytes = [value longLongValue];
    if (bytes < 0) {
        return [SeafResumableProbeResult resultWithKind:SeafResumableProbeInvalid uploadedBytes:0];
    }
    if (![self acceptsByteRanges:acceptRanges]) {
        return [SeafResumableProbeResult resultWithKind:SeafResumableProbeNotEnabled uploadedBytes:bytes];
    }
    return [SeafResumableProbeResult resultWithKind:SeafResumableProbeSupported uploadedBytes:bytes];
}

+ (SeafResumableAlignment)alignServerOffset:(long long)serverOffset
                            confirmedOffset:(long long)confirmedOffset
                                inflightEnd:(long long)inflightEnd
                               inflightHash:(NSString *)inflightHash
                          localInflightHash:(NSString *)localInflightHash
                                   fileSize:(long long)fileSize
                               finalPending:(BOOL)finalPending
{
    if (finalPending && serverOffset == fileSize) {
        return SeafResumableAlignCommitting;
    }
    if (serverOffset == confirmedOffset && serverOffset < fileSize) {
        return SeafResumableAlignContinue;
    }
    if (inflightEnd > confirmedOffset && serverOffset == inflightEnd && inflightEnd < fileSize) {
        if (inflightHash.length > 0 && [inflightHash isEqualToString:localInflightHash]) {
            return SeafResumableAlignAdvanceInflight;
        }
        return SeafResumableAlignContentChanged;
    }
    return SeafResumableAlignUntrusted;
}

#pragma mark - Segment responses

+ (BOOL)isCancellationError:(NSError *)error
{
    return [error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled;
}

+ (NSString *)bodyStringFromResponseObject:(id)responseObject error:(NSError *)error
{
    if ([responseObject isKindOfClass:[NSString class]]) return responseObject;
    if ([responseObject isKindOfClass:[NSDictionary class]]) {
        id msg = ((NSDictionary *)responseObject)[@"error"] ?: ((NSDictionary *)responseObject)[@"error_msg"];
        if ([msg isKindOfClass:[NSString class]]) return msg;
    }
    NSData *data = error.userInfo[kAFResponseDataKey];
    if ([data isKindOfClass:[NSData class]] && data.length > 0) {
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return nil;
}

+ (BOOL)body:(NSString *)body contains:(NSString *)needle
{
    return body.length > 0 && [body rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

+ (BOOL)isTerminalStatus:(NSInteger)status bodyString:(NSString *)bodyString
{
    switch (status) {
        case 440: // invalid file name
        case 442: // file too large
        case 443: // out of quota
        case 404:
            return YES;
        case 403:
            return ![self body:bodyString contains:@"Access token not found"];
        case 400:
            return [self body:bodyString contains:@"Parent dir doesn't exist"];
        default:
            return NO;
    }
}

/// `name` as committed for staging name `staging`: exact, or the server's auto-renamed `base (n).ext`.
+ (BOOL)isCommittedName:(NSString *)name forStagingName:(NSString *)staging
{
    if ([name isEqualToString:staging]) return YES;
    return [self isName:name candidateForTarget:staging];
}

+ (BOOL)isFileId:(id)value
{
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSString *s = value;
    if (s.length != 40) return NO;
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    return [s stringByTrimmingCharactersInSet:hex].length == 0;
}

+ (SeafResumableChunkResult *)committedResultFromBody:(id)body status:(NSInteger)status
{
    NSDictionary *entry = nil;
    if ([body isKindOfClass:[NSArray class]] && [(NSArray *)body count] == 1
        && [((NSArray *)body).firstObject isKindOfClass:[NSDictionary class]]) {
        entry = ((NSArray *)body).firstObject;
    }
    if (!entry) return nil;
    id name = entry[@"name"];
    id fileId = entry[@"id"];
    id size = entry[@"size"];
    if (![name isKindOfClass:[NSString class]] || ![size isKindOfClass:[NSNumber class]]) return nil;
    return [SeafResumableChunkResult resultWithOutcome:SeafResumableChunkCommitted status:status
                                                  name:name fileId:[fileId isKindOfClass:[NSString class]] ? fileId : nil
                                                  size:[size longLongValue]];
}

+ (SeafResumableChunkResult *)classifyChunkResponseWithStatus:(NSInteger)status
                                                         body:(id)body
                                                   bodyString:(NSString *)bodyString
                                                        error:(NSError *)error
                                                       isLast:(BOOL)isLast
                                                     fileSize:(long long)fileSize
                                                  stagingName:(NSString *)stagingName
{
    if ([self isCancellationError:error]) {
        return [SeafResumableChunkResult resultWithOutcome:SeafResumableChunkCancelled status:status];
    }
    // No HTTP answer, or a gateway/server failure: on the final segment the
    // server may still be committing, so the outcome is unknown.
    if (status == 0 || status >= 500) {
        return [SeafResumableChunkResult resultWithOutcome:isLast ? SeafResumableChunkUncertain : SeafResumableChunkTransient
                                                    status:status];
    }
    if (status >= 400) {
        // A 4xx is always sent before anything is committed (plan §6.3).
        if (status == 400 && [self body:bodyString contains:@"Upload offset is invalid"]) {
            return [SeafResumableChunkResult resultWithOutcome:SeafResumableChunkOffsetMismatch status:status];
        }
        if (status == 403 && [self body:bodyString contains:@"Access token not found"]) {
            return [SeafResumableChunkResult resultWithOutcome:SeafResumableChunkTokenExpired status:status];
        }
        if ([self isTerminalStatus:status bodyString:bodyString]) {
            return [SeafResumableChunkResult resultWithOutcome:SeafResumableChunkTerminal status:status];
        }
        return [SeafResumableChunkResult resultWithOutcome:SeafResumableChunkFallback status:status];
    }
    if (status < 200 || status >= 300) {
        return [SeafResumableChunkResult resultWithOutcome:isLast ? SeafResumableChunkUncertain : SeafResumableChunkTransient
                                                    status:status];
    }

    SeafResumableChunkResult *committed = [self committedResultFromBody:body status:status];
    if (!isLast) {
        if ([body isKindOfClass:[NSDictionary class]]
            && [((NSDictionary *)body)[@"success"] isKindOfClass:[NSNumber class]]
            && [((NSDictionary *)body)[@"success"] boolValue]) {
            return [SeafResumableChunkResult resultWithOutcome:SeafResumableChunkAccepted status:status];
        }
        // Anything else means the server took this segment as a whole file.
        return [SeafResumableChunkResult resultWithOutcome:SeafResumableChunkHeaderIgnored status:status
                                                      name:committed.committedName fileId:committed.committedId
                                                      size:committed ? committed.committedSize : -1];
    }

    if (!committed) {
        return [SeafResumableChunkResult resultWithOutcome:SeafResumableChunkUncertain status:status];
    }
    if (committed.committedSize != fileSize) {
        return [SeafResumableChunkResult resultWithOutcome:SeafResumableChunkHeaderIgnored status:status
                                                      name:committed.committedName fileId:committed.committedId
                                                      size:committed.committedSize];
    }
    if (![self isFileId:committed.committedId] || ![self isCommittedName:committed.committedName forStagingName:stagingName]) {
        return [SeafResumableChunkResult resultWithOutcome:SeafResumableChunkUncertain status:status];
    }
    return committed;
}

#pragma mark - Final segment confirmation

+ (SeafResumableFinalResolution)resolveFinalWithStagingExists:(BOOL)stagingExists
                                                  stagingSize:(long long)stagingSize
                                                 serverOffset:(long long)serverOffset
                                              confirmedOffset:(long long)confirmedOffset
                                                     fileSize:(long long)fileSize
                                         secondsSinceFinalSent:(NSTimeInterval)elapsed
{
    if (stagingExists) {
        return stagingSize == fileSize ? SeafResumableFinalCommitted : SeafResumableFinalDeleteGarbage;
    }
    if (serverOffset == fileSize) return SeafResumableFinalWait;
    if (serverOffset == confirmedOffset && serverOffset > 0) {
        return elapsed < 600 ? SeafResumableFinalWait : SeafResumableFinalResend;
    }
    if (serverOffset == 0) return SeafResumableFinalRecheck;
    return SeafResumableFinalNewAttempt;
}

#pragma mark - Rename confirmation

+ (BOOL)isName:(NSString *)name candidateForTarget:(NSString *)target
{
    if (name.length == 0 || target.length == 0) return NO;
    if ([name isEqualToString:target]) return YES;
    NSString *ext = target.pathExtension;
    NSString *base = ext.length > 0 ? [target stringByDeletingPathExtension] : target;
    NSString *suffix = ext.length > 0 ? [@"." stringByAppendingString:ext] : @"";
    NSString *prefix = [base stringByAppendingString:@" ("];
    if (![name hasPrefix:prefix] || ![name hasSuffix:[@")" stringByAppendingString:suffix]]) return NO;
    NSUInteger start = prefix.length;
    NSUInteger end = name.length - suffix.length - 1;
    if (end <= start) return NO;
    NSString *digits = [name substringWithRange:NSMakeRange(start, end - start)];
    return [digits stringByTrimmingCharactersInSet:[NSCharacterSet decimalDigitCharacterSet]].length == 0;
}

+ (NSDictionary<NSString *, NSString *> *)renameSnapshotFromListing:(NSArray<NSDictionary *> *)listing
                                                         targetName:(NSString *)targetName
{
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in listing) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *name = entry[@"name"];
        NSString *fileId = entry[@"id"];
        if (![name isKindOfClass:[NSString class]]) continue;
        name = [self normalizedName:name];
        if ([self isName:name candidateForTarget:targetName]) {
            snapshot[name] = [fileId isKindOfClass:[NSString class]] ? fileId : @"";
        }
    }
    return snapshot;
}

+ (SeafResumableRenameResolution)resolveRenameWithStagingExists:(BOOL)stagingExists
                                                        listing:(NSArray<NSDictionary *> *)listing
                                                       snapshot:(NSDictionary<NSString *, NSString *> *)snapshot
                                                     targetName:(NSString *)targetName
                                                            oid:(NSString *)oid
                                                  publishedName:(NSString **)publishedName
{
    if (stagingExists) return SeafResumableRenameRetry;
    NSDictionary *now = [self renameSnapshotFromListing:listing targetName:targetName];
    // Prefer the exact target name, then the lowest-numbered auto-renamed form.
    NSArray *names = [now.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        if ([a isEqualToString:targetName]) return NSOrderedAscending;
        if ([b isEqualToString:targetName]) return NSOrderedDescending;
        return [a compare:b options:NSNumericSearch];
    }];
    for (NSString *name in names) {
        if (![now[name] isEqualToString:oid]) continue;
        if ([snapshot[name] isEqualToString:oid]) continue; // was already there before the rename
        if (publishedName) *publishedName = name;
        return SeafResumableRenamePublished;
    }
    return SeafResumableRenameLost;
}

#pragma mark - Sweeping

+ (NSTimeInterval)recordLifetime { return 7 * 24 * 3600; }
+ (NSTimeInterval)takeOverAfter { return 24 * 3600; }

+ (SeafResumableSweepAction)sweepActionForRecord:(SeafResumableUploadRecord *)r
                                            live:(BOOL)live
                                             now:(NSTimeInterval)now
                                          reason:(NSString **)reason
{
    NSTimeInterval age = now - r.updatedAt;
    switch (r.state) {
        case SeafResumableStateDone:
            return age > [self recordLifetime] ? SeafResumableSweepDeleteRecord : SeafResumableSweepNone;
        case SeafResumableStateAbandoned:
            return r.stagingCommitted ? SeafResumableSweepDeleteStaging : SeafResumableSweepDeleteRecord;
        default:
            break;
    }
    if (live) return SeafResumableSweepNone;
    if (age > [self recordLifetime]) {
        if (reason) *reason = @"expired";
        return SeafResumableSweepAbandon;
    }
    // A share-extension task never runs again; any other task gets a day to come back itself.
    BOOL orphan = [r.entry isEqualToString:SeafResumableEntryShare];
    BOOL waited = orphan || age >= [self takeOverAfter];
    // Finishing needs no source file once the spot-check windows are saved.
    BOOL finishable = r.state == SeafResumableStateFinalPending || r.state == SeafResumableStateRenamePending
        || (r.state == SeafResumableStateCommitted && (r.verified || r.probeWindows != nil));
    if (finishable && waited) return SeafResumableSweepFinish;
    if (orphan && age >= [self takeOverAfter]) {
        if (reason) *reason = @"sweep-orphaned";
        return SeafResumableSweepAbandon;
    }
    return SeafResumableSweepNone;
}

@end
