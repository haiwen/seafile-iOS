//
//  SeafResumableUploadSweeper.m
//  Seafile
//

#import "SeafResumableUploadSweeper.h"
#import "SeafResumableUploadStore.h"
#import "SeafResumableUploadPolicy.h"
#import "SeafResumableUploadSession.h"
#import "SeafConnection+ResumableUpload.h"
#import "SeafStorage.h"
#import "Debug.h"

@implementation SeafResumableUploadSweeper

/// Finish-only sessions in flight; touched on the main queue only.
+ (NSMutableSet<SeafResumableUploadSession *> *)runningSessions
{
    static NSMutableSet *sessions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ sessions = [NSMutableSet set]; });
    return sessions;
}

+ (void)sweepForConnection:(SeafConnection *)connection
{
    SeafResumableUploadStore *store = [SeafResumableUploadStore sharedStore];
    NSString *account = connection.accountIdentifier;
    if (!store || account.length == 0) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self removeStaleChunkDirectories:store];
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        for (SeafResumableUploadRecord *r in [store recordsForAccount:account]) {
            [self sweepRecord:r store:store connection:connection now:now];
        }
        for (NSDictionary *t in [store tombstonesForAccount:account]) {
            [self checkTombstone:t store:store connection:connection now:now];
        }
    });
}

/// Segment body files of executions that are over (plan §9, item 5). An execution
/// removes its own directory when it ends, so what is left belongs to killed ones:
/// a directory goes once no live execution owns it and it has been untouched for
/// the heartbeat timeout, or at once when it is from an earlier launch of this app.
+ (void)removeStaleChunkDirectories:(SeafResumableUploadStore *)store
{
    NSSet<NSString *> *live = [store liveRunTokens];
    NSString *root = [SeafStorage.sharedObject.rootPath stringByAppendingPathComponent:@"upload-chunks"];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in [fm contentsOfDirectoryAtPath:root error:nil]) {
        NSString *path = [root stringByAppendingPathComponent:name];
        if ([live containsObject:name]) continue;
        NSDate *modified = [[fm attributesOfItemAtPath:path error:nil] fileModificationDate];
        BOOL untouched = modified && -[modified timeIntervalSinceNow] > store.staleAfter;
        if (untouched || [store isRunTokenOfEndedLaunch:name]) {
            [fm removeItemAtPath:path error:nil];
        }
    }
}

+ (void)sweepRecord:(SeafResumableUploadRecord *)r store:(SeafResumableUploadStore *)store
         connection:(SeafConnection *)connection now:(NSTimeInterval)now
{
    BOOL live = [store isRecordLive:r now:now];
    NSString *reason = nil;
    switch ([SeafResumableUploadPolicy sweepActionForRecord:r live:live now:now reason:&reason]) {
        case SeafResumableSweepNone:
            return;
        case SeafResumableSweepDeleteRecord:
            [store deleteAttempt:r.attemptId];
            return;
        case SeafResumableSweepDeleteStaging: {
            NSTimeInterval age = now - r.updatedAt;
            [self deleteStagingOf:r connection:connection then:^(BOOL gone) {
                if (gone || age > [SeafResumableUploadPolicy recordLifetime]) [store deleteAttempt:r.attemptId];
            }];
            return;
        }
        case SeafResumableSweepAbandon:
            [store abandonAttempt:r.attemptId reason:reason];
            return;
        case SeafResumableSweepFinish:
            [self finishRecord:r connection:connection];
            return;
    }
}

+ (void)deleteStagingOf:(SeafResumableUploadRecord *)r connection:(SeafConnection *)connection then:(void (^)(BOOL gone))then
{
    NSString *path = r.stagingPath;
    dispatch_async(dispatch_get_main_queue(), ^{
        [connection resumable_deleteFileInRepo:r.repoId path:path completion:^(NSInteger status, NSError *error) {
            BOOL gone = (status >= 200 && status < 300) || status == 404;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ then(gone); });
        }];
    });
}

/// An attempt that got as far as the final segment but whose task will not run
/// again (the share extension exited, or the task was gone for a day). The
/// session confirms, spot-checks with the saved windows and renames; it claims
/// the attempt itself, so a task that does come back is not run over.
+ (void)finishRecord:(SeafResumableUploadRecord *)record connection:(SeafConnection *)connection
{
    dispatch_async(dispatch_get_main_queue(), ^{
        SeafResumableUploadSession *session = [[SeafResumableUploadSession alloc] initToFinishRecord:record connection:connection];
        [[self runningSessions] addObject:session];
        [session startWithCompletion:^(SeafResumableOutcome outcome, NSString *oid, NSString *serverDate, NSError *error) {
            [[self runningSessions] removeObject:session];
        }];
    });
}

+ (void)checkTombstone:(NSDictionary *)t store:(SeafResumableUploadStore *)store
            connection:(SeafConnection *)connection now:(NSTimeInterval)now
{
    NSString *account = t[@"account"], *repoId = t[@"repo_id"], *dir = t[@"parent_dir"], *name = t[@"staging_name"];
    BOOL expired = now > [t[@"check_until"] doubleValue];
    NSString *path = [dir stringByAppendingPathComponent:name];
    dispatch_async(dispatch_get_main_queue(), ^{
        // Late duplicates of a final segment on old servers can recreate the staging name.
        [connection resumable_fileInfoInRepo:repoId path:path completion:^(NSInteger status, NSDictionary *info, NSError *error) {
            if (status == 200) {
                [connection resumable_deleteFileInRepo:repoId path:path completion:^(NSInteger deleteStatus, NSError *deleteError) {
                    Warning("[ResumableUpload] removed late staging file %@ (%ld)", path, (long)deleteStatus);
                }];
            }
            if (expired) {
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    [store removeTombstoneForAccount:account repoId:repoId parentDir:dir stagingName:name];
                });
            }
        }];
    });
}

@end
