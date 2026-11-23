//
//  Logic tests for resumable uploads (plan §13.2).
//  Pure Foundation + SQLite, compiled and run on macOS by run_tests.sh.
//

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <sqlite3.h>
#import "SeafResumableUploadPolicy.h"
#import "SeafResumableUploadStore.h"
#import "SeafChunkRequestBuilder.h"

static int gFailures = 0;
static int gChecks = 0;

#define CHECK(cond, ...) do { gChecks++; if (!(cond)) { gFailures++; \
    NSLog(@"FAIL %s:%d %@", __FILE__, __LINE__, [NSString stringWithFormat:__VA_ARGS__]); } } while (0)

typedef SeafResumableUploadPolicy P;

static NSError *URLError(NSInteger code) { return [NSError errorWithDomain:NSURLErrorDomain code:code userInfo:nil]; }

static NSString *SHA1Hex(NSData *data)
{
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static void testNaming(void)
{
    CHECK(![P shouldSegmentFileOfSize:SeafResumableMinFileSize - 1], @"10 MiB - 1");
    CHECK(![P shouldSegmentFileOfSize:SeafResumableMinFileSize], @"exactly 10 MiB");
    CHECK([P shouldSegmentFileOfSize:SeafResumableMinFileSize + 1], @"10 MiB + 1");

    NSString *hex = @"0123456789abcdef";
    CHECK([[P stagingNameForTargetName:@"IMG_0001.MOV" randomHex:hex] isEqualToString:@".seafile-upload-0123456789abcdef.MOV"], @"keeps ext");
    CHECK([[P stagingNameForTargetName:@"README" randomHex:hex] isEqualToString:@".seafile-upload-0123456789abcdef"], @"no ext");
    CHECK([[P stagingNameForTargetName:@"a.文档" randomHex:hex] isEqualToString:@".seafile-upload-0123456789abcdef"], @"non-ascii ext dropped");
    CHECK([[P stagingNameForTargetName:@"a.abcdefghijklmnopq" randomHex:hex] isEqualToString:@".seafile-upload-0123456789abcdef"], @"long ext dropped");
    NSString *random = [P stagingNameForTargetName:@"x.mp4"];
    CHECK([P isStagingName:random] && random.length == 16 + 16 + 4, @"random staging name %@", random);
    CHECK(![P isStagingName:@"seafile-upload-x"], @"prefix needs the dot");
    CHECK([[P normalizedName:@"é"] isEqualToString:@"é"], @"NFC");
    CHECK([P segmentCountForFileSize:SeafResumableChunkSize * 2 chunkSize:SeafResumableChunkSize] == 2, @"exact multiple");
    CHECK([P segmentCountForFileSize:SeafResumableChunkSize * 2 + 1 chunkSize:SeafResumableChunkSize] == 3, @"remainder");
    CHECK([P segmentEndForStart:0 fileSize:100 chunkSize:8] == 7, @"first end");
    CHECK([P segmentEndForStart:96 fileSize:100 chunkSize:8] == 99, @"last end");
}

static void testProbe(void)
{
    NSDictionary *ok = @{@"uploadedBytes": @(16)};
    CHECK([P interpretProbeWithStatus:0 acceptRanges:nil body:nil error:URLError(NSURLErrorCancelled)].kind == SeafResumableProbeCancelled, @"cancel");
    CHECK([P interpretProbeWithStatus:0 acceptRanges:nil body:nil error:URLError(NSURLErrorTimedOut)].kind == SeafResumableProbeTransient, @"timeout");
    CHECK([P interpretProbeWithStatus:500 acceptRanges:nil body:nil error:nil].kind == SeafResumableProbeTransient, @"500");
    CHECK([P interpretProbeWithStatus:502 acceptRanges:nil body:nil error:nil].kind == SeafResumableProbeTransient, @"502");
    CHECK([P interpretProbeWithStatus:404 acceptRanges:nil body:nil error:nil].kind == SeafResumableProbeTerminal, @"404");
    CHECK([P interpretProbeWithStatus:400 acceptRanges:@"bytes" body:nil error:nil].kind == SeafResumableProbeInvalid, @"400");
    CHECK([P interpretProbeWithStatus:200 acceptRanges:@"bytes" body:nil error:nil].kind == SeafResumableProbeInvalid, @"empty body");
    CHECK([P interpretProbeWithStatus:200 acceptRanges:@"bytes" body:@{} error:nil].kind == SeafResumableProbeInvalid, @"missing field");
    CHECK([P interpretProbeWithStatus:200 acceptRanges:@"bytes" body:@{@"uploadedBytes": @(-1)} error:nil].kind == SeafResumableProbeInvalid, @"negative");
    CHECK([P interpretProbeWithStatus:200 acceptRanges:@"bytes" body:@{@"uploadedBytes": @(1.5)} error:nil].kind == SeafResumableProbeInvalid, @"float");
    CHECK([P interpretProbeWithStatus:200 acceptRanges:@"bytes" body:@{@"uploadedBytes": @"16"} error:nil].kind == SeafResumableProbeInvalid, @"string");
    SeafResumableProbeResult *notEnabled = [P interpretProbeWithStatus:200 acceptRanges:nil body:ok error:nil];
    CHECK(notEnabled.kind == SeafResumableProbeNotEnabled && notEnabled.uploadedBytes == 16, @"no header keeps bytes for confirmation");
    CHECK([P interpretProbeWithStatus:200 acceptRanges:@"none" body:ok error:nil].kind == SeafResumableProbeNotEnabled, @"none");
    SeafResumableProbeResult *supported = [P interpretProbeWithStatus:200 acceptRanges:@"Bytes" body:ok error:nil];
    CHECK(supported.kind == SeafResumableProbeSupported && supported.uploadedBytes == 16, @"case-insensitive");
    CHECK([P interpretProbeWithStatus:200 acceptRanges:@"foo, bytes" body:ok error:nil].kind == SeafResumableProbeSupported, @"list");
}

static void testAlignment(void)
{
    long long size = 100;
    CHECK([P alignServerOffset:0 confirmedOffset:0 inflightEnd:0 inflightHash:nil localInflightHash:nil fileSize:size finalPending:NO] == SeafResumableAlignContinue, @"new attempt");
    CHECK([P alignServerOffset:40 confirmedOffset:40 inflightEnd:48 inflightHash:@"h" localInflightHash:@"x" fileSize:size finalPending:NO] == SeafResumableAlignContinue, @"in-flight lost");
    CHECK([P alignServerOffset:48 confirmedOffset:40 inflightEnd:48 inflightHash:@"h" localInflightHash:@"h" fileSize:size finalPending:NO] == SeafResumableAlignAdvanceInflight, @"advance");
    CHECK([P alignServerOffset:48 confirmedOffset:40 inflightEnd:48 inflightHash:@"h" localInflightHash:@"x" fileSize:size finalPending:NO] == SeafResumableAlignContentChanged, @"changed");
    CHECK([P alignServerOffset:48 confirmedOffset:40 inflightEnd:48 inflightHash:nil localInflightHash:@"h" fileSize:size finalPending:NO] == SeafResumableAlignContentChanged, @"no stored hash");
    CHECK([P alignServerOffset:100 confirmedOffset:96 inflightEnd:100 inflightHash:@"h" localInflightHash:@"h" fileSize:size finalPending:YES] == SeafResumableAlignCommitting, @"committing");
    CHECK([P alignServerOffset:100 confirmedOffset:96 inflightEnd:100 inflightHash:@"h" localInflightHash:@"h" fileSize:size finalPending:NO] == SeafResumableAlignUntrusted, @"size but not pending");
    CHECK([P alignServerOffset:0 confirmedOffset:40 inflightEnd:0 inflightHash:nil localInflightHash:nil fileSize:size finalPending:NO] == SeafResumableAlignUntrusted, @"lost temp file");
    CHECK([P alignServerOffset:32 confirmedOffset:40 inflightEnd:0 inflightHash:nil localInflightHash:nil fileSize:size finalPending:NO] == SeafResumableAlignUntrusted, @"smaller");
    CHECK([P alignServerOffset:56 confirmedOffset:40 inflightEnd:48 inflightHash:@"h" localInflightHash:@"h" fileSize:size finalPending:NO] == SeafResumableAlignUntrusted, @"beyond in-flight");
}

static SeafResumableChunkOutcome Classify(NSInteger status, id body, NSString *text, NSError *error, BOOL last)
{
    return [P classifyChunkResponseWithStatus:status body:body bodyString:text error:error isLast:last fileSize:100
                                  stagingName:@".seafile-upload-0123456789abcdef.mov"].outcome;
}

static void testChunk(void)
{
    NSString *staging = @".seafile-upload-0123456789abcdef.mov";
    NSString *fid = @"0123456789abcdef0123456789abcdef01234567";
    NSArray *good = @[@{@"name": staging, @"id": fid, @"size": @100}];
    CHECK(Classify(0, nil, nil, URLError(NSURLErrorCancelled), NO) == SeafResumableChunkCancelled, @"cancel");
    CHECK(Classify(200, @{@"success": @YES}, nil, nil, NO) == SeafResumableChunkAccepted, @"accepted");
    CHECK(Classify(200, good, nil, nil, NO) == SeafResumableChunkHeaderIgnored, @"intermediate committed");
    CHECK(Classify(200, @"\"abc\"", nil, nil, NO) == SeafResumableChunkHeaderIgnored, @"intermediate odd body");
    CHECK(Classify(200, good, nil, nil, YES) == SeafResumableChunkCommitted, @"final ok");
    SeafResumableChunkResult *r = [P classifyChunkResponseWithStatus:200 body:good bodyString:nil error:nil isLast:YES fileSize:100 stagingName:staging];
    CHECK([r.committedName isEqualToString:staging] && [r.committedId isEqualToString:fid] && r.committedSize == 100, @"committed fields");
    CHECK(Classify(200, @[@{@"name": staging, @"id": fid, @"size": @8}], nil, nil, YES) == SeafResumableChunkHeaderIgnored, @"final size mismatch");
    CHECK(Classify(200, @[@{@"name": @".seafile-upload-0123456789abcdef (1).mov", @"id": fid, @"size": @100}], nil, nil, YES) == SeafResumableChunkCommitted, @"auto-renamed staging");
    CHECK(Classify(200, @[@{@"name": @"other.mov", @"id": fid, @"size": @100}], nil, nil, YES) == SeafResumableChunkUncertain, @"other name");
    CHECK(Classify(200, @[@{@"name": staging, @"id": @"xyz", @"size": @100}], nil, nil, YES) == SeafResumableChunkUncertain, @"bad id");
    CHECK(Classify(200, @{@"success": @YES}, nil, nil, YES) == SeafResumableChunkUncertain, @"final unparseable");
    CHECK(Classify(400, nil, @"{\"error\": \"Upload offset is invalid.\n\"}", nil, NO) == SeafResumableChunkOffsetMismatch, @"offset");
    CHECK(Classify(400, nil, @"Upload offset is invalid.\n", nil, YES) == SeafResumableChunkOffsetMismatch, @"offset final, plain text");
    CHECK(Classify(403, nil, @"Access token not found", nil, NO) == SeafResumableChunkTokenExpired, @"token");
    CHECK(Classify(403, nil, @"Permission denied", nil, NO) == SeafResumableChunkTerminal, @"403 perm");
    for (NSNumber *code in @[@440, @442, @443, @404]) {
        CHECK(Classify(code.integerValue, nil, nil, nil, YES) == SeafResumableChunkTerminal, @"%@ terminal", code);
    }
    CHECK(Classify(400, nil, @"Parent dir doesn't exist.\n", nil, YES) == SeafResumableChunkTerminal, @"parent dir");
    CHECK(Classify(400, nil, @"Invalid filename in mime header.", nil, NO) == SeafResumableChunkFallback, @"other 400");
    CHECK(Classify(413, nil, nil, nil, NO) == SeafResumableChunkFallback, @"413");
    CHECK(Classify(500, nil, nil, nil, NO) == SeafResumableChunkTransient, @"500 intermediate");
    CHECK(Classify(502, nil, nil, nil, YES) == SeafResumableChunkUncertain, @"502 final");
    CHECK(Classify(0, nil, nil, URLError(NSURLErrorNetworkConnectionLost), YES) == SeafResumableChunkUncertain, @"lost final");
    CHECK(Classify(0, nil, nil, URLError(NSURLErrorNetworkConnectionLost), NO) == SeafResumableChunkTransient, @"lost intermediate");

    NSError *afError = [NSError errorWithDomain:@"AF" code:1 userInfo:@{@"com.alamofire.serialization.response.error.data": [@"Upload offset is invalid.\n" dataUsingEncoding:NSUTF8StringEncoding]}];
    CHECK([[P bodyStringFromResponseObject:nil error:afError] hasPrefix:@"Upload offset"], @"raw body");
    CHECK([[P bodyStringFromResponseObject:@{@"error": @"x"} error:nil] isEqualToString:@"x"], @"json error");
}

static void testFinalAndRename(void)
{
    CHECK([P resolveFinalWithStagingExists:YES stagingSize:100 serverOffset:0 confirmedOffset:96 fileSize:100 secondsSinceFinalSent:1] == SeafResumableFinalCommitted, @"committed");
    CHECK([P resolveFinalWithStagingExists:YES stagingSize:8 serverOffset:0 confirmedOffset:96 fileSize:100 secondsSinceFinalSent:1] == SeafResumableFinalDeleteGarbage, @"garbage");
    CHECK([P resolveFinalWithStagingExists:NO stagingSize:-1 serverOffset:100 confirmedOffset:96 fileSize:100 secondsSinceFinalSent:1] == SeafResumableFinalWait, @"committing");
    CHECK([P resolveFinalWithStagingExists:NO stagingSize:-1 serverOffset:96 confirmedOffset:96 fileSize:100 secondsSinceFinalSent:30] == SeafResumableFinalWait, @"queued");
    CHECK([P resolveFinalWithStagingExists:NO stagingSize:-1 serverOffset:96 confirmedOffset:96 fileSize:100 secondsSinceFinalSent:601] == SeafResumableFinalResend, @"resend");
    CHECK([P resolveFinalWithStagingExists:NO stagingSize:-1 serverOffset:0 confirmedOffset:96 fileSize:100 secondsSinceFinalSent:1] == SeafResumableFinalRecheck, @"recheck");
    CHECK([P resolveFinalWithStagingExists:NO stagingSize:-1 serverOffset:40 confirmedOffset:96 fileSize:100 secondsSinceFinalSent:1] == SeafResumableFinalNewAttempt, @"other");

    CHECK([P isName:@"a.mov" candidateForTarget:@"a.mov"], @"exact");
    CHECK([P isName:@"a (1).mov" candidateForTarget:@"a.mov"], @"(1)");
    CHECK([P isName:@"a (12).mov" candidateForTarget:@"a.mov"], @"(12)");
    CHECK(![P isName:@"a (x).mov" candidateForTarget:@"a.mov"], @"(x)");
    CHECK(![P isName:@"a(1).mov" candidateForTarget:@"a.mov"], @"no space");
    CHECK(![P isName:@"b (1).mov" candidateForTarget:@"a.mov"], @"other base");
    CHECK([P isName:@"README (2)" candidateForTarget:@"README"], @"no ext");

    NSString *oid = @"1111111111111111111111111111111111111111";
    NSArray *listing = @[@{@"name": @"a.mov", @"id": @"2222222222222222222222222222222222222222"},
                         @{@"name": @"a (1).mov", @"id": oid},
                         @{@"name": @"other.txt", @"id": oid}];
    NSDictionary *snapshot = @{@"a.mov": @"2222222222222222222222222222222222222222"};
    NSString *published = nil;
    CHECK([P resolveRenameWithStagingExists:YES listing:listing snapshot:snapshot targetName:@"a.mov" oid:oid publishedName:&published] == SeafResumableRenameRetry, @"staging still there");
    CHECK([P resolveRenameWithStagingExists:NO listing:listing snapshot:snapshot targetName:@"a.mov" oid:oid publishedName:&published] == SeafResumableRenamePublished
          && [published isEqualToString:@"a (1).mov"], @"found (1): %@", published);
    NSDictionary *snapshotHadIt = @{@"a.mov": @"2222222222222222222222222222222222222222", @"a (1).mov": oid};
    CHECK([P resolveRenameWithStagingExists:NO listing:listing snapshot:snapshotHadIt targetName:@"a.mov" oid:oid publishedName:&published] == SeafResumableRenameLost, @"pre-existing copy is not ours");
    NSDictionary *snap = [P renameSnapshotFromListing:listing targetName:@"a.mov"];
    CHECK(snap.count == 2 && snap[@"other.txt"] == nil, @"snapshot keeps candidates only");

}

static void testProbeWindow(void)
{
    NSData *ab = [NSData dataWithBytes:"ab" length:2];
    SeafProbeWindow *w = [SeafProbeWindow windowWithOffset:8 length:2 sha1:SHA1Hex(ab)];
    CHECK([w matchesData:ab], @"same bytes");
    CHECK(![w matchesData:[NSData dataWithBytes:"\0\0" length:2]], @"hole");
    CHECK(![w matchesData:[NSData dataWithBytes:"abc" length:3]], @"length");
    CHECK(![w matchesData:nil], @"no data");
    SeafProbeWindow *upper = [SeafProbeWindow windowWithOffset:8 length:2 sha1:SHA1Hex(ab).uppercaseString];
    CHECK([upper matchesData:ab], @"hex case");
    SeafProbeWindow *back = [SeafProbeWindow windowWithDictionary:w.dictionaryRepresentation];
    CHECK([back isEqual:w], @"dictionary round trip");
    CHECK(([SeafProbeWindow windowWithDictionary:@{@"offset": @-1, @"length": @2, @"sha1": SHA1Hex(ab)}] == nil), @"negative offset");
    CHECK(([SeafProbeWindow windowWithDictionary:@{@"offset": @0, @"length": @0, @"sha1": SHA1Hex(ab)}] == nil), @"empty window");
    CHECK(([SeafProbeWindow windowWithDictionary:@{@"offset": @0, @"length": @2, @"sha1": @"abc"}] == nil), @"short hash");
    CHECK(([SeafProbeWindow windowWithDictionary:@{@"offset": @"0", @"length": @2, @"sha1": SHA1Hex(ab)}] == nil), @"string offset");
    CHECK([SeafProbeWindow windowWithDictionary:@[]] == nil, @"not a dict");
}

static SeafResumableUploadRecord *SweepRecord(SeafResumableState state, NSString *entry, NSTimeInterval age)
{
    SeafResumableUploadRecord *r = [SeafResumableUploadRecord new];
    r.state = state;
    r.entry = entry;
    r.updatedAt = 1000000 - age;
    return r;
}

static void testSweepPolicy(void)
{
    NSTimeInterval now = 1000000, day = 24 * 3600, week = 7 * day;
    NSString *reason = nil;
#define SWEEP(rec, isLive) [P sweepActionForRecord:(rec) live:(isLive) now:now reason:&reason]
    CHECK(SWEEP(SweepRecord(SeafResumableStateDone, @"manual", day), NO) == SeafResumableSweepNone, @"fresh receipt kept");
    CHECK(SWEEP(SweepRecord(SeafResumableStateDone, @"manual", week + 1), NO) == SeafResumableSweepDeleteRecord, @"old receipt dropped");
    SeafResumableUploadRecord *abandoned = SweepRecord(SeafResumableStateAbandoned, @"manual", 0);
    CHECK(SWEEP(abandoned, NO) == SeafResumableSweepDeleteRecord, @"abandoned, no file");
    abandoned.stagingCommitted = YES;
    CHECK(SWEEP(abandoned, NO) == SeafResumableSweepDeleteStaging, @"abandoned with file");
    CHECK(SWEEP(abandoned, YES) == SeafResumableSweepDeleteStaging, @"abandoned ignores owner");

    // Share-extension attempts are finished once nobody holds them.
    SeafResumableUploadRecord *final = SweepRecord(SeafResumableStateFinalPending, SeafResumableEntryShare, 10 * 60);
    CHECK(SWEEP(final, YES) == SeafResumableSweepNone, @"live owner left alone");
    CHECK(SWEEP(final, NO) == SeafResumableSweepFinish, @"share final pending finished");
    SeafResumableUploadRecord *committed = SweepRecord(SeafResumableStateCommitted, SeafResumableEntryShare, 10 * 60);
    CHECK(SWEEP(committed, NO) == SeafResumableSweepNone, @"no windows: cannot check yet");
    committed.probeWindows = @[];
    CHECK(SWEEP(committed, NO) == SeafResumableSweepFinish, @"windows saved: finish");
    SeafResumableUploadRecord *verified = SweepRecord(SeafResumableStateCommitted, SeafResumableEntryShare, 10 * 60);
    verified.verified = YES;
    CHECK(SWEEP(verified, NO) == SeafResumableSweepFinish, @"verified: rename");
    CHECK(SWEEP(SweepRecord(SeafResumableStateRenamePending, SeafResumableEntryShare, 10 * 60), NO) == SeafResumableSweepFinish, @"rename pending");
    CHECK(SWEEP(SweepRecord(SeafResumableStateUploading, SeafResumableEntryShare, 10 * 60), NO) == SeafResumableSweepNone, @"share mid-upload kept a day");
    reason = nil;
    CHECK(SWEEP(SweepRecord(SeafResumableStateUploading, SeafResumableEntryShare, day), NO) == SeafResumableSweepAbandon
          && [reason isEqualToString:@"sweep-orphaned"], @"share mid-upload given up after a day: %@", reason);
    reason = nil;
    CHECK(SWEEP(SweepRecord(SeafResumableStateCommitted, SeafResumableEntryShare, day), NO) == SeafResumableSweepAbandon
          && [reason isEqualToString:@"sweep-orphaned"], @"share unverifiable given up");

    // Other entries get a day to come back themselves.
    CHECK(SWEEP(SweepRecord(SeafResumableStateFinalPending, @"manual", day - 1), NO) == SeafResumableSweepNone, @"manual waits");
    CHECK(SWEEP(SweepRecord(SeafResumableStateFinalPending, @"extension", day), NO) == SeafResumableSweepFinish, @"after a day: finish");
    CHECK(SWEEP(SweepRecord(SeafResumableStateRenamePending, nil, day), NO) == SeafResumableSweepFinish, @"old record without entry");
    CHECK(SWEEP(SweepRecord(SeafResumableStateUploading, @"manual", week - 1), NO) == SeafResumableSweepNone, @"manual mid-upload kept");
    CHECK(SWEEP(SweepRecord(SeafResumableStateCommitted, @"manual", day), NO) == SeafResumableSweepNone, @"manual unverifiable waits for its task");
    reason = nil;
    CHECK(SWEEP(SweepRecord(SeafResumableStateUploading, @"manual", week + 1), NO) == SeafResumableSweepAbandon
          && [reason isEqualToString:@"expired"], @"expired: %@", reason);
    reason = nil;
    CHECK(SWEEP(SweepRecord(SeafResumableStateRenamePending, SeafResumableEntryShare, week + 1), NO) == SeafResumableSweepAbandon
          && [reason isEqualToString:@"expired"], @"a week of failed finishing gives up");
    CHECK(SWEEP(SweepRecord(SeafResumableStateUploading, @"manual", week + 1), YES) == SeafResumableSweepNone, @"live never expires");
#undef SWEEP
}

static SeafResumableUploadRecord *NewRecord(NSString *task, NSString *target, NSString *token)
{
    SeafResumableUploadRecord *r = [SeafResumableUploadRecord new];
    r.taskId = task;
    r.account = @"acct";
    r.repoId = @"repo";
    r.parentDir = @"/dir";
    r.targetName = target;
    r.stagingName = [P stagingNameForTargetName:target];
    r.fileSize = 100;
    r.runToken = token;
    return r;
}

static void testStore(NSString *dir)
{
    NSString *path = [dir stringByAppendingPathComponent:@"store.sqlite"];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    SeafResumableUploadStore *a = [[SeafResumableUploadStore alloc] initWithPath:path];
    SeafResumableUploadStore *b = [[SeafResumableUploadStore alloc] initWithPath:path]; // a second process
    CHECK(a && b, @"open");

    SeafResumableUploadRecord *r1 = NewRecord(@"task1", @"a.mov", @"run1");
    NSArray *replaced = nil;
    CHECK([a insertAttempt:r1 replaced:&replaced] == SeafResumableClaimGranted && replaced.count == 0, @"insert");
    CHECK([[b recordForTaskId:@"task1"].attemptId isEqualToString:r1.attemptId], @"visible to the other connection");

    SeafResumableUploadRecord *sameTarget = NewRecord(@"task2", @"a.mov", @"run2");
    CHECK([b insertAttempt:sameTarget replaced:nil] == SeafResumableClaimBusy, @"target busy across connections");
    CHECK([b claimAttempt:r1.attemptId runToken:@"run2"] == SeafResumableClaimBusy, @"claim busy");
    CHECK([a claimAttempt:r1.attemptId runToken:@"run1"] == SeafResumableClaimGranted, @"own claim");

    r1.confirmedOffset = 48;
    r1.chunkHashes = @[@"h1", @"h2"];
    r1.renameSnapshot = @{@"a.mov": @"x"};
    r1.entry = SeafResumableEntryShare;
    NSString *h = SHA1Hex([NSData dataWithBytes:"ab" length:2]);
    r1.probeWindows = @[[SeafProbeWindow windowWithOffset:0 length:2 sha1:h], [SeafProbeWindow windowWithOffset:9 length:2 sha1:h]];
    CHECK([a saveRecord:r1], @"save");
    SeafResumableUploadRecord *wrong = [r1 copy];
    wrong.runToken = @"intruder";
    wrong.confirmedOffset = 96;
    CHECK(![b saveRecord:wrong], @"save without ownership");
    SeafResumableUploadRecord *loaded = [b recordForTaskId:@"task1"];
    CHECK(loaded.confirmedOffset == 48 && [loaded.chunkHashes isEqualToArray:(@[@"h1", @"h2"])]
          && [loaded.renameSnapshot[@"a.mov"] isEqualToString:@"x"], @"round trip %@", loaded);
    CHECK([loaded.entry isEqualToString:SeafResumableEntryShare] && [loaded.probeWindows isEqualToArray:r1.probeWindows], @"entry and windows round trip");
    SeafResumableUploadRecord *copied = [[b recordForTaskId:@"task1"] copy];
    CHECK(copied.probeWindows.count == 2, @"copy keeps windows");
    SeafResumableUploadRecord *noWindows = NewRecord(@"task5", @"c.mov", @"run5");
    [a insertAttempt:noWindows replaced:nil];
    CHECK([b recordWithAttemptId:noWindows.attemptId].probeWindows == nil, @"no windows stays nil");
    noWindows.probeWindows = @[];
    CHECK([a saveRecord:noWindows] && [b recordWithAttemptId:noWindows.attemptId].probeWindows.count == 0
          && [b recordWithAttemptId:noWindows.attemptId].probeWindows != nil, @"empty windows differ from none");
    [a deleteAttempt:noWindows.attemptId];

    [a releaseAttempt:r1.attemptId runToken:@"run1"];
    CHECK([b claimAttempt:r1.attemptId runToken:@"run3"] == SeafResumableClaimGranted, @"released record is claimable");
    CHECK([a heartbeatAttempt:r1.attemptId runToken:@"run1"] == NO, @"old owner lost it");

    // A stale owner is replaced by a new attempt of another task on the same target.
    b.staleAfter = 0;
    CHECK([b insertAttempt:sameTarget replaced:&replaced] == SeafResumableClaimGranted && replaced.count == 1, @"stale replaced");
    CHECK([b recordWithAttemptId:r1.attemptId].state == SeafResumableStateAbandoned, @"old attempt abandoned");
    b.staleAfter = 300;

    // A relaunched main app takes over what its previous launch left, without
    // waiting for the heartbeat; an extension's execution keeps the heartbeat rule.
    SeafResumableUploadStore *launch1 = [[SeafResumableUploadStore alloc] initWithPath:path];
    SeafResumableUploadStore *launch2 = [[SeafResumableUploadStore alloc] initWithPath:path];
    launch1.mainAppLaunchId = @"L1";
    launch2.mainAppLaunchId = @"L2";
    NSString *token1 = [launch1 makeRunToken], *token2 = [launch2 makeRunToken];
    CHECK(![launch1 isRunTokenOfEndedLaunch:token1] && [launch2 isRunTokenOfEndedLaunch:token1]
          && ![b isRunTokenOfEndedLaunch:token1] && ![launch2 isRunTokenOfEndedLaunch:@"run1"], @"ended launch tokens");
    SeafResumableUploadRecord *killed = NewRecord(@"task6", @"d.mov", token1);
    CHECK([launch1 insertAttempt:killed replaced:nil] == SeafResumableClaimGranted, @"insert in launch 1");
    CHECK([launch1 claimAttempt:killed.attemptId runToken:[launch1 makeRunToken]] == SeafResumableClaimBusy, @"same launch waits");
    CHECK([b claimAttempt:killed.attemptId runToken:@"ext1"] == SeafResumableClaimBusy, @"extension waits for the app's heartbeat");
    CHECK([[launch1 liveRunTokens] containsObject:token1] && ![[launch2 liveRunTokens] containsObject:token1], @"live tokens");
    CHECK([launch2 isRecordLive:[launch2 recordWithAttemptId:killed.attemptId] now:[NSDate date].timeIntervalSince1970] == NO, @"dead for the next launch");
    CHECK([launch2 claimAttempt:killed.attemptId runToken:token2] == SeafResumableClaimGranted, @"next launch takes over at once");
    CHECK([[launch2 liveRunTokens] containsObject:token2], @"new owner live");
    [launch2 releaseAttempt:killed.attemptId runToken:token2];
    CHECK([b claimAttempt:killed.attemptId runToken:@"ext1"] == SeafResumableClaimGranted, @"extension claims a released attempt");
    CHECK([launch2 claimAttempt:killed.attemptId runToken:token2] == SeafResumableClaimBusy, @"app waits for a live extension");
    [b deleteAttempt:killed.attemptId];

    sameTarget.state = SeafResumableStateDone;
    sameTarget.finalName = @"a.mov";
    sameTarget.oid = @"oid";
    CHECK([b saveRecord:sameTarget], @"done");
    CHECK([a recordForTaskId:@"task2"].state == SeafResumableStateDone, @"receipt");
    [a acknowledgeTaskId:@"task2"];
    CHECK([a recordForTaskId:@"task2"] == nil, @"acknowledged");

    SeafResumableUploadRecord *r4 = NewRecord(@"task4", @"b.mov", @"run4");
    [a insertAttempt:r4 replaced:nil];
    [b abandonTaskIds:@[@"task4"] reason:@"user"];
    CHECK([a recordWithAttemptId:r4.attemptId].state == SeafResumableStateAbandoned, @"user cancel");

    [a addTombstoneForAccount:@"acct" repoId:@"repo" parentDir:@"/dir" stagingName:@"s" checkUntil:1];
    CHECK([b tombstonesForAccount:@"acct"].count == 1, @"tombstone");
    [b removeTombstoneForAccount:@"acct" repoId:@"repo" parentDir:@"/dir" stagingName:@"s"];
    CHECK([a tombstonesForAccount:@"acct"].count == 0, @"tombstone removed");

    CHECK(![a isSegmentingDisabledForAccount:@"acct" serverVersion:@"13.0.29"], @"enabled");
    [a markNotEnabledForAccount:@"acct"];
    CHECK([b isSegmentingDisabledForAccount:@"acct" serverVersion:@"13.0.29"], @"not enabled");
    [a disableForAccount:@"acct2" serverVersion:@"12.0.14" reason:@"holes"];
    CHECK([a isSegmentingDisabledForAccount:@"acct2" serverVersion:@"12.0.14"], @"version bound");
    CHECK(![a isSegmentingDisabledForAccount:@"acct2" serverVersion:@"13.0.29"], @"new version re-enables");
    CHECK([a noteOffsetRegressionForAccount:@"acct3"] == 1 && [b noteOffsetRegressionForAccount:@"acct3"] == 2, @"regressions");

    [a deleteAllForAccount:@"acct"];
    CHECK([b recordsForAccount:@"acct"].count == 0, @"account cleared");
}

static void testBuilder(NSString *dir)
{
    NSString *src = [dir stringByAppendingPathComponent:@"source.bin"];
    NSMutableData *content = [NSMutableData dataWithLength:1000];
    for (NSUInteger i = 0; i < content.length; i++) ((uint8_t *)content.mutableBytes)[i] = (uint8_t)(i % 251);
    memset((uint8_t *)content.mutableBytes + 400, 0, 200); // a zero region
    [content writeToFile:src atomically:YES];

    NSString *outDir = [dir stringByAppendingPathComponent:@"chunks"];
    NSError *error = nil;
    SeafChunkRequest *req = [SeafChunkRequestBuilder buildRequestForURL:[NSURL URLWithString:@"https://h/seafhttp/upload-api/t"]
                                                              filePath:src start:300 end:699 fileSize:1000
                                                           stagingName:@".seafile-upload-0123456789abcdef.bin"
                                                             parentDir:@"/dir" lastModify:@"2026-11-20T10:00:00+08:00"
                                                           isLastChunk:NO outputDirectory:outDir error:&error];
    CHECK(req != nil, @"build %@", error);
    NSURLRequest *r = req.request;
    CHECK([r.URL.absoluteString isEqualToString:@"https://h/seafhttp/upload-api/t?ret-json=1"], @"ret-json %@", r.URL);
    CHECK([[r valueForHTTPHeaderField:@"Content-Range"] isEqualToString:@"bytes 300-699/1000"], @"range");
    CHECK([[r valueForHTTPHeaderField:@"Content-Disposition"] isEqualToString:@"attachment; filename=\".seafile-upload-0123456789abcdef.bin\""], @"disposition");
    CHECK([r valueForHTTPHeaderField:@"Authorization"] == nil, @"no token");
    NSData *body = [NSData dataWithContentsOfURL:req.bodyFileURL];
    CHECK([[r valueForHTTPHeaderField:@"Content-Length"] longLongValue] == (long long)body.length, @"length");
    NSString *text = [[NSString alloc] initWithData:body encoding:NSISOLatin1StringEncoding];
    CHECK([text containsString:@"name=\"file\"; filename=\".seafile-upload-0123456789abcdef.bin\""], @"part filename");
    CHECK([text containsString:@"name=\"last_modify\"\r\n\r\n2026-11-20T10:00:00+08:00"], @"last_modify");
    CHECK([text containsString:@"name=\"file_mtime\"\r\n\r\n2026-11-20T10:00:00+08:00"], @"file_mtime");
    CHECK(![text containsString:@"name=\"replace\""], @"no replace");
    NSData *segment = [content subdataWithRange:NSMakeRange(300, 400)];
    CHECK([body rangeOfData:segment options:0 range:NSMakeRange(0, body.length)].location != NSNotFound, @"segment bytes");
    CHECK([req.segmentHash isEqualToString:[SeafChunkRequestBuilder sha1OfFileAtPath:src start:300 length:400]], @"hash");
    CHECK(req.request.timeoutInterval == 60, @"timeout");
    [SeafChunkRequestBuilder removeBodyFile:req];
    CHECK(![[NSFileManager defaultManager] fileExistsAtPath:req.bodyFileURL.path], @"body removed");

    SeafChunkRequest *last = [SeafChunkRequestBuilder buildRequestForURL:[NSURL URLWithString:@"https://h/u?x=1"] filePath:src
                                                                   start:700 end:999 fileSize:1000 stagingName:@"s" parentDir:@"/"
                                                              lastModify:nil isLastChunk:YES outputDirectory:outDir error:&error];
    CHECK([last.request.URL.absoluteString isEqualToString:@"https://h/u?x=1&ret-json=1"], @"query append");
    CHECK(last.request.timeoutInterval == 600, @"final timeout");
    CHECK(![[[NSString alloc] initWithData:[NSData dataWithContentsOfURL:last.bodyFileURL] encoding:NSISOLatin1StringEncoding] containsString:@"last_modify"], @"no mtime fields");

    NSArray<SeafProbeWindow *> *windows = [SeafChunkRequestBuilder probeWindowsForFileAtPath:src fileSize:1000 chunkSize:200 windowLength:16 error:&error];
    CHECK(windows.count == 4, @"zero segment [400,600) skipped, got %lu", (unsigned long)windows.count);
    for (SeafProbeWindow *w in windows) {
        CHECK(w.offset < 400 || w.offset >= 600, @"window in zero area %lld", w.offset);
        NSData *bytes = [content subdataWithRange:NSMakeRange((NSUInteger)w.offset, w.length)];
        CHECK(w.length == 16 && [w matchesData:bytes], @"window hash at %lld", w.offset);
        NSMutableData *hole = [NSMutableData dataWithLength:w.length];
        CHECK(![w matchesData:hole], @"zero-filled read rejected at %lld", w.offset);
    }
}

/// A store created before the entry / probe_windows columns existed.
static void testStoreMigration(NSString *dir)
{
    NSString *path = [dir stringByAppendingPathComponent:@"old-store.sqlite"];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    sqlite3 *db = NULL;
    sqlite3_open(path.fileSystemRepresentation, &db);
    const char *oldSchema = "CREATE TABLE attempts ("
        "attempt_id TEXT PRIMARY KEY, task_id TEXT NOT NULL, account TEXT NOT NULL, repo_id TEXT NOT NULL, "
        "parent_dir TEXT NOT NULL, target_name TEXT NOT NULL, target_key TEXT NOT NULL, staging_name TEXT NOT NULL, "
        "overwrite INTEGER NOT NULL DEFAULT 0, file_size INTEGER NOT NULL, last_modify TEXT, file_identity TEXT, "
        "chunk_size INTEGER NOT NULL, chunk_hashes TEXT NOT NULL DEFAULT '', confirmed_offset INTEGER NOT NULL DEFAULT 0, "
        "inflight_end INTEGER NOT NULL DEFAULT 0, inflight_hash TEXT, state INTEGER NOT NULL, final_sent_at REAL NOT NULL DEFAULT 0, "
        "committed_name TEXT, oid TEXT, rename_snapshot TEXT, final_name TEXT, staging_committed INTEGER NOT NULL DEFAULT 0, "
        "verified INTEGER NOT NULL DEFAULT 0, run_token TEXT, heartbeat_at REAL NOT NULL DEFAULT 0, reason TEXT, "
        "created_at REAL NOT NULL, updated_at REAL NOT NULL);"
        "INSERT INTO attempts (attempt_id, task_id, account, repo_id, parent_dir, target_name, target_key, staging_name, "
        "file_size, chunk_size, state, created_at, updated_at) VALUES ('old', 't', 'acct', 'r', '/', 'a', 'acct|r|/|a', 's', 9, 8, 2, 1, 1);";
    CHECK(sqlite3_exec(db, oldSchema, NULL, NULL, NULL) == SQLITE_OK, @"old schema");
    sqlite3_close(db);

    SeafResumableUploadStore *store = [[SeafResumableUploadStore alloc] initWithPath:path];
    CHECK(store != nil, @"opens an old store");
    SeafResumableUploadRecord *old = [store recordWithAttemptId:@"old"];
    CHECK(old && old.state == SeafResumableStateCommitted && old.entry == nil && old.probeWindows == nil, @"old row readable: %@", old);
    SeafResumableUploadRecord *r = NewRecord(@"t2", @"b", @"run");
    r.entry = @"manual";
    CHECK([store insertAttempt:r replaced:nil] == SeafResumableClaimGranted, @"insert after migration");
    CHECK([[store recordWithAttemptId:r.attemptId].entry isEqualToString:@"manual"], @"new column written");
    SeafResumableUploadStore *again = [[SeafResumableUploadStore alloc] initWithPath:path];
    CHECK(again != nil, @"migration runs once");

    // A damaged window list is dropped rather than half-read.
    sqlite3_open(path.fileSystemRepresentation, &db);
    sqlite3_exec(db, "UPDATE attempts SET probe_windows = '[{\"offset\":0,\"length\":2,\"sha1\":\"x\"}]' WHERE attempt_id = 'old'", NULL, NULL, NULL);
    sqlite3_close(db);
    CHECK([again recordWithAttemptId:@"old"].probeWindows == nil, @"damaged windows dropped");
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"resumable-logic-tests"];
        if (argc > 1) dir = [NSString stringWithUTF8String:argv[1]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        testNaming();
        testProbe();
        testAlignment();
        testChunk();
        testFinalAndRename();
        testProbeWindow();
        testSweepPolicy();
        testStore(dir);
        testStoreMigration(dir);
        testBuilder(dir);
        NSLog(@"%d checks, %d failures", gChecks, gFailures);
        return gFailures == 0 ? 0 : 1;
    }
}
