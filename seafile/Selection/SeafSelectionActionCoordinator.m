//
//  SeafSelectionActionCoordinator.m
//  seafile
//

#import "SeafSelectionActionCoordinator.h"

#import "SeafGlobal.h"
#import "SeafActionsManager.h"
#import "SeafDataTaskManager.h"
#import "UIViewController+Extend.h"
#import "SeafFile.h"
#import "SeafDir.h"
#import "SeafStorage.h"
#import "SVProgressHUD.h"
#import "Debug.h"

#import <Photos/Photos.h>
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, SeafSelectionMediaClass) {
    SeafSelectionAllMedia = 0,
    SeafSelectionAllNonMedia = 1,
    SeafSelectionMixed = 2,
};

@interface SeafSelectionActionCoordinator ()

@property (nonatomic, weak) UIViewController *hostVC;

// Aggregated album save progress
@property (atomic) NSInteger albumSaveTotalCount;
@property (atomic) NSInteger albumSaveCompletedCount;
@property (atomic) NSInteger albumSaveFailedCount;
@property (atomic) BOOL albumSaveInProgress;

// Aggregated download progress
@property (nonatomic, assign) BOOL isAggregatingDownload;
@property (nonatomic, strong) NSMutableSet<NSString *> *aggregateTrackedKeys;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *aggregateFileSizes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *aggregateDownloadedBytes;
@property (nonatomic, assign) long long aggregateTotalBytes;
@property (nonatomic, assign) long long aggregateCachedBytes;
@property (nonatomic, assign) long long aggregateDownloadedSoFar;
@property (nonatomic, assign) NSInteger aggregateFilesTracked;
@property (nonatomic, assign) NSInteger aggregateFilesCompleted;
@property (nonatomic, assign) NSInteger aggregateFilesFailed;
@property (nonatomic, assign) CFTimeInterval aggregateLastHUDUpdateTs;
@property (nonatomic, assign) float aggregateLastProgress;

// Unified progress for All-Media: Download(75%) + Album Save(25%)
@property (nonatomic, assign) BOOL unifiedAllMediaProgressActive;
@property (nonatomic, strong) NSTimer *aggregateHUDHeartbeat;

// Custom overlay
@property (nonatomic, strong) UIView *aggregateOverlayView;
@property (nonatomic, strong) UIProgressView *aggregateProgressView;
@property (nonatomic, strong) UILabel *aggregateStatusLabel;
@property (nonatomic, strong) UILabel *aggregateDetailLabel;
@property (nonatomic, strong) UIView *aggregateBackdropView;
@property (nonatomic, strong) UIButton *aggregateCancelButton;
@property (nonatomic, strong) NSArray<SeafFile *> *aggregateFiles;
@property (nonatomic, assign) BOOL aggregateOverlayEnabled;
@property (nonatomic, strong) NSByteCountFormatter *aggregateByteFormatter;
@property (nonatomic, assign) CFTimeInterval aggregateLastDetailUpdateTs;

@end

@implementation SeafSelectionActionCoordinator

- (instancetype)initWithHostViewController:(UIViewController *)hostViewController
{
    self = [super init];
    if (self) {
        _hostVC = hostViewController;
    }
    return self;
}

- (BOOL)isAggregating
{
    return self.isAggregatingDownload || (self.unifiedAllMediaProgressActive && self.albumSaveInProgress);
}

#pragma mark - Public entry points

- (void)handleSelectedItems:(NSArray<SeafBase *> *)items
                 sourceView:(UIView *)sourceView
{
    __weak typeof(self) weakSelf = self;
    [self collectFilesRecursivelyFromItems:items completion:^(NSArray<SeafFile *> *files) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (files.count == 0) return;
        
        SeafSelectionMediaClass cls = [self classifyFiles:files];
        switch (cls) {
            case SeafSelectionAllMedia: {
                self.aggregateOverlayEnabled = YES;
                if (self.albumSaveInProgress) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self.aggregateOverlayView) {
                            self.aggregateStatusLabel.text = NSLocalizedString(@"Saving to album", @"Seafile");
                        } else {
                        }
                    });
                    break;
                }
                self.unifiedAllMediaProgressActive = YES;
                [self.hostVC checkPhotoLibraryAuth:^{
                    __weak typeof(self) weakSelf2 = self;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf2) self = weakSelf2;
                        if (!self) return;
                        [self startAggregateDownloadForFiles:files postAction:^{
                            [self saveMediaFilesToAlbum:files];
                        }];
                    });
                }];
                break;
            }
            case SeafSelectionAllNonMedia: {
                self.aggregateOverlayEnabled = NO;
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.unifiedAllMediaProgressActive = NO;
                    [self startAggregateDownloadForFiles:files postAction:nil];
                });
                break;
            }
            case SeafSelectionMixed: {
                self.aggregateOverlayEnabled = YES;
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.unifiedAllMediaProgressActive = NO;
                    [self startAggregateDownloadForFiles:files postAction:^{
                        [self waitAndCollectExportURLsForFiles:files maxRetry:30 interval:0.3 completion:^(NSArray<NSURL *> *urls, NSArray<SeafFile *> *missing) {
                            [SeafActionsManager exportByActivityView:urls item:sourceView targerVC:self.hostVC];
                            if (missing.count > 0) {
                                [SVProgressHUD showInfoWithStatus:NSLocalizedString(@"Some files were not ready yet", @"Seafile")];
                            }
                        }];
                    }];
                });
                break;
            }
        }
    }];
}

- (void)updateAggregateProgressForEntry:(SeafBase *)entry
                               progress:(float)progress
{
    if (!self.isAggregatingDownload) return;
    if (![entry isKindOfClass:[SeafFile class]]) return;
    SeafFile *file = (SeafFile *)entry;
    NSString *key = [self uniqueKeyForFile:file];
    if (![self.aggregateTrackedKeys containsObject:key]) return;
    NSNumber *sizeNum = self.aggregateFileSizes[key];
    if (!sizeNum) return;
    long long size = sizeNum.longLongValue;
    long long currentBytes = (long long)(progress * (double)size);
    if (currentBytes < 0) currentBytes = 0;
    if (currentBytes > size) currentBytes = size;
    long long prev = [self.aggregateDownloadedBytes[key] longLongValue];
    if (currentBytes < prev) currentBytes = prev;
    long long delta = currentBytes - prev;
    if (delta != 0) {
        self.aggregateDownloadedSoFar += delta;
        self.aggregateDownloadedBytes[key] = @(currentBytes);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshAggregateHUDProgressWithStatus:NSLocalizedString(@"Downloading file", @"Seafile")];
    });
}

- (void)notifyFileDownloadCompleted:(SeafFile *)file
                              error:(NSError * _Nullable)error
{
    if (!self.isAggregatingDownload) return;
    NSString *key = [self uniqueKeyForFile:file];
    if (![self.aggregateTrackedKeys containsObject:key]) return;
    if (error) {
        self.aggregateFilesFailed += 1;
    } else {
        long long size = [self.aggregateFileSizes[key] longLongValue];
        long long prev = [self.aggregateDownloadedBytes[key] longLongValue];
        if (size > prev) {
            self.aggregateDownloadedSoFar += (size - prev);
            self.aggregateDownloadedBytes[key] = @(size);
        }
        self.aggregateFilesCompleted += 1;
        [file loadCache];
        (void)[file exportURL];
        [self refreshAggregateHUDProgressWithStatus:NSLocalizedString(@"Downloading file", @"Seafile")];
    }
    [self.aggregateTrackedKeys removeObject:key];
    [self finalizeAggregateIfNeeded];
}

#pragma mark - Expand and classify

- (void)collectFilesRecursivelyFromItems:(NSArray<SeafBase *> *)items
                              completion:(void (^)(NSArray<SeafFile *> *files))completion
{
    if (items.count == 0) {
        if (completion) completion(@[]);
        return;
    }
    dispatch_queue_t workQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_group_t group = dispatch_group_create();
    __block NSMutableArray<SeafFile *> *collected = [NSMutableArray new];
    
    __block void (^processEntry)(SeafBase *entry);
    processEntry = ^(SeafBase *entry) {
        if (!entry) return;
        if ([entry isKindOfClass:[SeafFile class]]) {
            @synchronized (collected) {
                [collected addObject:(SeafFile *)entry];
            }
            return;
        }
        if ([entry isKindOfClass:[SeafDir class]]) {
            SeafDir *dir = (SeafDir *)entry;
            dispatch_group_enter(group);
            [dir loadContentSuccess:^(SeafDir *d) {
                for (SeafBase *child in d.items) {
                    processEntry(child);
                }
                dispatch_group_leave(group);
            } failure:^(SeafDir *d, NSError *error) {
                Warning("Failed to load dir for expansion: %@, error: %@", d.path, error);
                dispatch_group_leave(group);
            }];
            return;
        }
    };
    for (SeafBase *item in items) {
        processEntry(item);
    }
    dispatch_group_notify(group, workQueue, ^{
        NSArray<SeafFile *> *result;
        @synchronized (collected) {
            result = [collected copy];
        }
        if (completion) completion(result);
    });
}

- (NSString *)uniqueKeyForFile:(SeafFile *)file
{
    NSString *repo = file.repoId ?: @"";
    NSString *path = file.path ?: @"";
    if (repo.length > 0 || path.length > 0) {
        return [NSString stringWithFormat:@"%@:%@", repo, path];
    }
    NSString *oid = file.oid;
    if (oid.length > 0) {
        return [NSString stringWithFormat:@"oid:%@", oid];
    }
    if ([file respondsToSelector:@selector(key)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id fallback = [file performSelector:@selector(key)];
#pragma clang diagnostic pop
        if ([fallback isKindOfClass:[NSString class]] && [(NSString *)fallback length] > 0) {
            return (NSString *)fallback;
        }
    }
    return [NSString stringWithFormat:@"ptr:%p", file];
}

- (SeafSelectionMediaClass)classifyFiles:(NSArray<SeafFile *> *)files
{
    if (files.count == 0) return SeafSelectionAllNonMedia;
    NSInteger mediaCount = 0, nonMediaCount = 0;
    for (SeafFile *f in files) {
        if ([f isImageFile] || [f isVideoFile]) mediaCount++;
        else nonMediaCount++;
        if (mediaCount > 0 && nonMediaCount > 0) return SeafSelectionMixed;
    }
    if (mediaCount == files.count) return SeafSelectionAllMedia;
    return SeafSelectionAllNonMedia;
}

#pragma mark - Aggregate download

- (void)startAggregateDownloadForFiles:(NSArray<SeafFile *> *)files
                           postAction:(void (^)(void))postAction
{
    if (self.isAggregatingDownload) {
        return;
    }
    self.isAggregatingDownload = YES;
    self.aggregateFiles = files;
    self.aggregateTrackedKeys = [NSMutableSet new];
    self.aggregateFileSizes = [NSMutableDictionary new];
    self.aggregateDownloadedBytes = [NSMutableDictionary new];
    self.aggregateTotalBytes = 0;
    self.aggregateCachedBytes = 0;
    self.aggregateDownloadedSoFar = 0;
    self.aggregateFilesTracked = 0;
    self.aggregateFilesCompleted = 0;
    self.aggregateFilesFailed = 0;
    self.aggregateLastProgress = -1.0f;
    self.aggregateLastHUDUpdateTs = 0;
    self.aggregateLastDetailUpdateTs = 0;
    self.aggregateByteFormatter = nil;
    NSMutableSet<NSString *> *seenKeys = [NSMutableSet new];

    for (SeafFile *file in files) {
        long long size = file.filesize;
        NSString *key = [self uniqueKeyForFile:file];
        if (key.length == 0) continue;
        if ([seenKeys containsObject:key]) {
            continue;
        }
        [seenKeys addObject:key];
        if ([file hasCache] || file.exportURL) {
            self.aggregateCachedBytes += size;
            continue;
        }
        self.aggregateTotalBytes += size;
        self.aggregateFilesTracked += 1;
        self.aggregateFileSizes[key] = @(size);
        self.aggregateDownloadedBytes[key] = @(0);
        [self.aggregateTrackedKeys addObject:key];
    }
    if (self.aggregateFilesTracked == 0) {
        self.isAggregatingDownload = NO;
        if (postAction) postAction();
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.aggregateOverlayEnabled) {
            if (!self.aggregateOverlayView) {
                // Backdrop to block interactions
                if (!self.aggregateBackdropView) {
                    UIView *container = self.hostVC.view.window ?: UIApplication.sharedApplication.keyWindow ?: self.hostVC.view;
                    UIView *backdrop = [[UIView alloc] initWithFrame:container.bounds];
                    backdrop.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
                    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                    backdrop.userInteractionEnabled = YES; // Swallow touches
                    self.aggregateBackdropView = backdrop;
                    [container addSubview:backdrop];
                }
                CGFloat horizontalMargin = 28.0;
                CGFloat containerWidth = self.aggregateBackdropView.bounds.size.width;
                CGFloat overlayWidth = MAX(160.0, containerWidth - horizontalMargin * 2.0);
                CGFloat overlayHeight = 148.0;
                CGRect frame = CGRectMake((containerWidth - overlayWidth) / 2.0, 0, overlayWidth, overlayHeight);
                
                UIView *overlay = [[UIView alloc] initWithFrame:frame];
                overlay.backgroundColor = [UIColor blackColor]; // fully opaque panel
                overlay.layer.cornerRadius = 14.0;
                overlay.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
                overlay.center = CGPointMake(CGRectGetMidX(self.aggregateBackdropView.bounds), CGRectGetMidY(self.aggregateBackdropView.bounds));
                
                UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, overlay.bounds.size.width - 32, 22)];
                label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
                label.textColor = [UIColor colorWithWhite:1.0 alpha:0.95];
                label.textAlignment = NSTextAlignmentCenter;
                label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
                label.text = NSLocalizedString(@"Downloading file", @"Seafile");
                [overlay addSubview:label];
                
                UIProgressView *pv = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
                pv.frame = CGRectMake(16, CGRectGetMaxY(label.frame) + 12, overlay.bounds.size.width - 32, 6);
                pv.progressTintColor = [UIColor colorWithWhite:1.0 alpha:0.95];
                pv.trackTintColor = [UIColor colorWithWhite:1.0 alpha:0.25];
                pv.layer.cornerRadius = 3.0;
                pv.clipsToBounds = YES;
                pv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
                pv.transform = CGAffineTransformMakeScale(1.0, 1.4);
                [overlay addSubview:pv];

                UILabel *detail = [[UILabel alloc] initWithFrame:CGRectMake(16, CGRectGetMaxY(pv.frame) + 10, overlay.bounds.size.width - 32, 18)];
                detail.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
                detail.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
                detail.textAlignment = NSTextAlignmentCenter;
                detail.autoresizingMask = UIViewAutoresizingFlexibleWidth;
                detail.text = [self aggregateProgressDetailString];
                [overlay addSubview:detail];
                
                UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
                cancel.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
                [cancel setTitle:STR_CANCEL forState:UIControlStateNormal];
                [cancel setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                cancel.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
                cancel.layer.cornerRadius = 10.0;
                cancel.clipsToBounds = YES;
                CGFloat btnH = 36.0;
                cancel.frame = CGRectMake(20, CGRectGetMaxY(detail.frame) + 14, overlay.bounds.size.width - 40, btnH);
                cancel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
                [cancel addTarget:self action:@selector(cancelAggregateFlow) forControlEvents:UIControlEventTouchUpInside];
                [overlay addSubview:cancel];
                
                self.aggregateOverlayView = overlay;
                self.aggregateProgressView = pv;
                self.aggregateStatusLabel = label;
                self.aggregateDetailLabel = detail;
                self.aggregateCancelButton = cancel;
                self.aggregateLastDetailUpdateTs = CACurrentMediaTime();
                
                overlay.alpha = 0.0;
                [self.aggregateBackdropView addSubview:overlay];
                [UIView animateWithDuration:0.15 animations:^{
                    overlay.alpha = 1.0;
                }];
            } else {
                self.aggregateStatusLabel.text = NSLocalizedString(@"Downloading file", @"Seafile");
                self.aggregateProgressView.progress = 0.0f;
                self.aggregateDetailLabel.text = [self aggregateProgressDetailString] ?: @"";
                self.aggregateLastDetailUpdateTs = CACurrentMediaTime();
            }
            [self startAggregateHUDHeartbeatIfNeeded];
        } else {
            if (self.aggregateOverlayView) {
                [self.aggregateOverlayView removeFromSuperview];
                self.aggregateOverlayView = nil;
                self.aggregateProgressView = nil;
                self.aggregateStatusLabel = nil;
                self.aggregateDetailLabel = nil;
                self.aggregateCancelButton = nil;
                self.aggregateLastDetailUpdateTs = 0;
            }
            if (self.aggregateBackdropView) {
                [self.aggregateBackdropView removeFromSuperview];
                self.aggregateBackdropView = nil;
            }
            if (self.aggregateHUDHeartbeat && [self.aggregateHUDHeartbeat isValid]) {
                [self.aggregateHUDHeartbeat invalidate];
                self.aggregateHUDHeartbeat = nil;
            }
        }
    });
    for (SeafFile *file in files) {
        NSString *key = [self uniqueKeyForFile:file];
        if (![self.aggregateTrackedKeys containsObject:key]) continue;
        __weak typeof(self) weakSelf = self;
        [file setFileDownloadedBlock:^(SeafFile * _Nonnull f, NSError * _Nullable error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            NSString *k = [self uniqueKeyForFile:f];
            if (![self.aggregateTrackedKeys containsObject:k]) {
                [f setFileDownloadedBlock:nil];
                return;
            }
            if (self.isAggregatingDownload) {
                if (error) {
                    self.aggregateFilesFailed += 1;
                } else {
                    long long size = [self.aggregateFileSizes[k] longLongValue];
                    long long prev = [self.aggregateDownloadedBytes[k] longLongValue];
                    if (size > prev) {
                        self.aggregateDownloadedSoFar += (size - prev);
                        self.aggregateDownloadedBytes[k] = @(size);
                    }
                    self.aggregateFilesCompleted += 1;
                    [f loadCache];
                    (void)[f exportURL];
                    [self refreshAggregateHUDProgressWithStatus:NSLocalizedString(@"Downloading file", @"Seafile")];
                }
                [self.aggregateTrackedKeys removeObject:k];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self finalizeAggregateIfNeeded];
                });
            }
            [f setFileDownloadedBlock:nil];
        }];
        [SeafDataTaskManager.sharedObject addFileDownloadTask:file];
    }
    objc_setAssociatedObject(self, @selector(startAggregateDownloadForFiles:postAction:), postAction, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)refreshAggregateHUDProgressWithStatus:(NSString *)status
{
    if (!self.isAggregatingDownload) return;
    if (!self.aggregateOverlayEnabled && !self.aggregateOverlayView) return;
    double denom = (double)(self.aggregateCachedBytes + self.aggregateTotalBytes);
    float overall = 0.0f;
    if (denom > 0.0) {
        overall = (float)((self.aggregateCachedBytes + self.aggregateDownloadedSoFar) / denom);
    } else if (self.aggregateFilesTracked > 0) {
        NSInteger tracked = self.aggregateFilesTracked;
        NSInteger done = self.aggregateFilesCompleted + self.aggregateFilesFailed;
        if (done < 0) done = 0;
        if (done > tracked) done = tracked;
        overall = tracked > 0 ? (float)done / (float)tracked : 0.0f;
    }
    float shown = self.unifiedAllMediaProgressActive ? (0.75f * overall) : overall;
    if (shown < 0.0f) shown = 0.0f;
    if (shown > 1.0f) shown = 1.0f;
    CFTimeInterval now = CACurrentMediaTime();
    if (self.aggregateLastProgress >= 0.f && shown < self.aggregateLastProgress) {
        shown = self.aggregateLastProgress;
    }
    BOOL shouldUpdateProgress = (self.aggregateLastProgress < 0.f) ||
                                (fabsf(shown - self.aggregateLastProgress) >= 0.002f) ||
                                (now - self.aggregateLastHUDUpdateTs >= 0.2);
    BOOL shouldUpdateDetail = shouldUpdateProgress ||
                              (now - self.aggregateLastDetailUpdateTs >= 0.3);
    if (!shouldUpdateProgress && !shouldUpdateDetail) {
        return;
    }
    if (shouldUpdateProgress) {
        self.aggregateLastProgress = shown;
        self.aggregateLastHUDUpdateTs = now;
    }
    if (shouldUpdateDetail) {
        self.aggregateLastDetailUpdateTs = now;
    }
    float targetProgress = self.aggregateLastProgress;
    BOOL updateProgress = shouldUpdateProgress;
    BOOL updateDetail = shouldUpdateDetail;
    NSString *statusCopy = status;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.aggregateOverlayView) {
            [self ensureAggregateOverlayWithStatus:statusCopy initialProgress:targetProgress];
            return;
        }
        if (updateProgress) {
            self.aggregateProgressView.progress = targetProgress;
            self.aggregateStatusLabel.text = statusCopy ?: NSLocalizedString(@"Downloading file", @"Seafile");
        } else if (statusCopy.length > 0) {
            self.aggregateStatusLabel.text = statusCopy;
        }
        if (updateDetail && self.aggregateDetailLabel) {
            self.aggregateDetailLabel.text = [self aggregateProgressDetailString];
        }
    });
}

- (NSByteCountFormatter *)currentAggregateByteFormatter
{
    if (!self.aggregateByteFormatter) {
        NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
        formatter.countStyle = NSByteCountFormatterCountStyleFile;
        formatter.allowsNonnumericFormatting = NO;
        self.aggregateByteFormatter = formatter;
    }
    return self.aggregateByteFormatter;
}

- (NSString *)aggregateProgressDetailString
{
    long long totalBytes = self.aggregateCachedBytes + self.aggregateTotalBytes;
    long long completedBytes = self.aggregateCachedBytes + self.aggregateDownloadedSoFar;
    if (completedBytes < 0) completedBytes = 0;
    if (totalBytes > 0) {
        if (completedBytes > totalBytes) {
            completedBytes = totalBytes;
        }
        NSByteCountFormatter *formatter = [self currentAggregateByteFormatter];
        NSString *completedString = [formatter stringFromByteCount:completedBytes];
        NSString *totalString = [formatter stringFromByteCount:totalBytes];
        return [NSString stringWithFormat:@"%@ / %@", completedString, totalString];
    }
    NSInteger tracked = self.aggregateFilesTracked;
    if (tracked > 0) {
        NSInteger done = self.aggregateFilesCompleted + self.aggregateFilesFailed;
        if (done < 0) done = 0;
        if (done > tracked) done = tracked;
        return [NSString stringWithFormat:NSLocalizedString(@"%ld of %ld files", @"Seafile"), (long)done, (long)tracked];
    }
    return (self.aggregateOverlayEnabled || self.isAggregatingDownload)
        ? NSLocalizedString(@"Preparing...", @"Seafile")
        : @"";
}

- (void)finalizeAggregateIfNeeded
{
    if (!self.isAggregatingDownload) return;
    if (self.aggregateFilesCompleted + self.aggregateFilesFailed < self.aggregateFilesTracked) return;
    self.isAggregatingDownload = NO;
    if (!self.unifiedAllMediaProgressActive) {
        self.aggregateOverlayEnabled = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.aggregateOverlayView) {
                [UIView animateWithDuration:0.15 animations:^{
                    self.aggregateOverlayView.alpha = 0.0;
                } completion:^(BOOL finished) {
                    [self.aggregateOverlayView removeFromSuperview];
                    self.aggregateOverlayView = nil;
                    self.aggregateProgressView = nil;
                    self.aggregateStatusLabel = nil;
                    self.aggregateDetailLabel = nil;
                    self.aggregateCancelButton = nil;
                    [self.aggregateBackdropView removeFromSuperview];
                    self.aggregateBackdropView = nil;
                    self.aggregateLastDetailUpdateTs = 0;
                }];
            }
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.aggregateOverlayView) {
                [self ensureAggregateOverlayWithStatus:NSLocalizedString(@"Saving to album", @"Seafile") initialProgress:0.75f];
            } else {
                self.aggregateProgressView.progress = 0.75f;
                self.aggregateStatusLabel.text = NSLocalizedString(@"Saving to album", @"Seafile");
            }
            self.aggregateLastProgress = 0.75f;
            self.aggregateLastHUDUpdateTs = CACurrentMediaTime();
        });
    }
    [self.aggregateHUDHeartbeat invalidate];
    self.aggregateHUDHeartbeat = nil;
    void (^postAction)(void) = objc_getAssociatedObject(self, @selector(startAggregateDownloadForFiles:postAction:));
    if (postAction) {
        objc_setAssociatedObject(self, @selector(startAggregateDownloadForFiles:postAction:), nil, OBJC_ASSOCIATION_ASSIGN);
        postAction();
    }
}

#pragma mark - Media save pipeline

- (void)saveMediaFilesToAlbum:(NSArray<SeafFile *> *)files
{
    NSMutableArray<SeafFile *> *mediaFiles = [NSMutableArray new];
    for (SeafFile *file in files) {
        if ([file isImageFile]) {
            [mediaFiles addObject:file];
        } else if ([file isVideoFile]) {
            [mediaFiles addObject:file];
        }
    }
    self.albumSaveTotalCount = mediaFiles.count;
    self.albumSaveCompletedCount = 0;
    self.albumSaveFailedCount = 0;
    self.albumSaveInProgress = (self.albumSaveTotalCount > 0);
    if (self.albumSaveTotalCount == 0) return;
    
    if (self.unifiedAllMediaProgressActive && !self.aggregateOverlayView) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self ensureAggregateOverlayWithStatus:NSLocalizedString(@"Saving to album", @"Seafile") initialProgress:0.75f];
            [self startAggregateHUDHeartbeatIfNeeded];
        });
    }
    for (SeafFile *file in mediaFiles) {
        [self waitAndSaveMediaFile:file maxRetry:30 interval:0.3];
    }
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    SeafFile *file = (__bridge SeafFile *)contextInfo;
    if (error) {
    }
    [self onSingleAlbumSaveFinishedWithError:(error != nil)];
}

- (void)video:(NSString *)videoPath didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    SeafFile *file = (__bridge SeafFile *)contextInfo;
    if (error) {
    }
    [self onSingleAlbumSaveFinishedWithError:(error != nil)];
}

- (void)saveSingleMediaFile:(SeafFile *)file retry:(NSInteger)retryCount
{
    if (!self.albumSaveInProgress) return;
    NSURL *exportURL = file.exportURL;
    NSString *path = exportURL ? exportURL.path : [file cachePath];
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path ?: @""];
    if (!exists && retryCount > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.albumSaveInProgress) {
                [self saveSingleMediaFile:file retry:retryCount - 1];
            }
        });
        return;
    }
    if ([file isImageFile]) {
        UIImage *img = exists ? [UIImage imageWithContentsOfFile:path] : nil;
        if (img) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIImageWriteToSavedPhotosAlbum(img, self, @selector(image:didFinishSavingWithError:contextInfo:), (__bridge void *)(file));
            });
        } else if (retryCount > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self.albumSaveInProgress) {
                    [self saveSingleMediaFile:file retry:retryCount - 1];
                }
            });
        } else {
            [self onSingleAlbumSaveFinishedWithError:YES];
        }
    } else if ([file isVideoFile]) {
        BOOL compatible = path ? UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(path) : NO;
        if (exists && compatible) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UISaveVideoAtPathToSavedPhotosAlbum(path, self, @selector(video:didFinishSavingWithError:contextInfo:), (__bridge void *)(file));
            });
        } else if (retryCount > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self.albumSaveInProgress) {
                    [self saveSingleMediaFile:file retry:retryCount - 1];
                }
            });
        } else {
            [self onSingleAlbumSaveFinishedWithError:YES];
        }
    } else {
        [self onSingleAlbumSaveFinishedWithError:YES];
    }
}

- (void)waitAndSaveMediaFile:(SeafFile *)file maxRetry:(NSInteger)maxRetry interval:(NSTimeInterval)interval
{
    if (!self.albumSaveInProgress) return;
    NSURL *exportURL = file.exportURL;
    NSString *exportPath = exportURL ? exportURL.path : nil;
    BOOL ready = exportPath ? [[NSFileManager defaultManager] fileExistsAtPath:exportPath] : NO;
    if (ready) {
        [self saveSingleMediaFile:file retry:5];
        return;
    }
    if (maxRetry <= 0) {
        [self onSingleAlbumSaveFinishedWithError:YES];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.albumSaveInProgress) {
            [self waitAndSaveMediaFile:file maxRetry:maxRetry - 1 interval:interval];
        }
    });
}

- (void)waitAndCollectExportURLsForFiles:(NSArray<SeafFile *> *)files
                                maxRetry:(NSInteger)maxRetry
                                interval:(NSTimeInterval)interval
                              completion:(void (^)(NSArray<NSURL *> *urls, NSArray<SeafFile *> *missing))completion
{
    NSMutableArray<NSURL *> *ready = [NSMutableArray new];
    NSMutableArray<SeafFile *> *notReady = [NSMutableArray new];
    for (SeafFile *f in files) {
        [f loadCache];
        NSURL *u = f.exportURL;
        BOOL exportExists = (u && [[NSFileManager defaultManager] fileExistsAtPath:u.path]);
        NSString *cachePath = [f cachePath];
        BOOL cacheExists = (cachePath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:cachePath]);
        if (exportExists) {
            [ready addObject:u];
        } else {
            // Fallback for non-media files: use cachePath if present
            if (cacheExists) {
                NSURL *fileURL = [NSURL fileURLWithPath:cachePath];
                if (fileURL) {
                    [ready addObject:fileURL];
                    continue;
                }
            }
            // Attempt last-resort document path fallback if ooid is missing but oid file exists
            NSString *docPath = nil;
            if (f.oid.length > 0) {
                docPath = [SeafStorage.sharedObject documentPath:f.oid];
                if (docPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:docPath]) {
                    [f setOoid:f.oid];
                    NSURL *docURL = [NSURL fileURLWithPath:docPath];
                    if (docURL) {
                        [ready addObject:docURL];
                        continue;
                    }
                }
            }
            // Retry once more for exportURL after loadCache
            u = f.exportURL;
            exportExists = (u && [[NSFileManager defaultManager] fileExistsAtPath:u.path]);
            if (exportExists) {
                [ready addObject:u];
                continue;
            }
            [notReady addObject:f];
        }
    }
    if (notReady.count == 0 || maxRetry <= 0) {
        if (completion) completion([ready copy], [notReady copy]);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self waitAndCollectExportURLsForFiles:files maxRetry:maxRetry - 1 interval:interval completion:completion];
    });
}

- (void)onSingleAlbumSaveFinishedWithError:(BOOL)failed
{
    if (!self.albumSaveInProgress) return;
    if (failed) self.albumSaveFailedCount += 1;
    self.albumSaveCompletedCount += 1;
    if (self.unifiedAllMediaProgressActive && self.albumSaveTotalCount > 0) {
        float saveProgress = (float)self.albumSaveCompletedCount / (float)self.albumSaveTotalCount;
            if (saveProgress < 0.f) saveProgress = 0.f;
            if (saveProgress > 1.f) saveProgress = 1.f;
            float unified = 0.75f + 0.25f * saveProgress;
            if (!self.aggregateOverlayView && (self.aggregateOverlayEnabled || self.unifiedAllMediaProgressActive)) {
                [self ensureAggregateOverlayWithStatus:NSLocalizedString(@"Saving to album", @"Seafile") initialProgress:unified];
            }
            if (self.aggregateOverlayView) {
                self.aggregateProgressView.progress = unified;
                self.aggregateStatusLabel.text = NSLocalizedString(@"Saving to album", @"Seafile");
            }
    }
    if (self.albumSaveCompletedCount >= self.albumSaveTotalCount) {
        self.albumSaveInProgress = NO;
        if (self.albumSaveFailedCount > 0) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Save failed", @"Seafile")];
        } else {
            [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Successfully saved", @"Seafile")];
        }
        self.unifiedAllMediaProgressActive = NO;
        [self.aggregateHUDHeartbeat invalidate];
        self.aggregateHUDHeartbeat = nil;
        if (self.aggregateOverlayView) {
            [UIView animateWithDuration:0.15 animations:^{
                self.aggregateOverlayView.alpha = 0.0;
            } completion:^(BOOL finished) {
                [self.aggregateOverlayView removeFromSuperview];
                self.aggregateOverlayView = nil;
                self.aggregateProgressView = nil;
                self.aggregateStatusLabel = nil;
                self.aggregateDetailLabel = nil;
                self.aggregateCancelButton = nil;
                [self.aggregateBackdropView removeFromSuperview];
                self.aggregateBackdropView = nil;
                self.aggregateLastDetailUpdateTs = 0;
            }];
        }
    }
}

#pragma mark - HUD overlay helpers

- (void)pingAggregateHUD
{
    if (!self.isAggregatingDownload && !(self.unifiedAllMediaProgressActive && self.albumSaveInProgress)) {
        [self.aggregateHUDHeartbeat invalidate];
        self.aggregateHUDHeartbeat = nil;
        return;
    }
    float shown = 0.f;
    NSString *status = nil;
    if (self.unifiedAllMediaProgressActive) {
        if (self.albumSaveInProgress && self.albumSaveTotalCount > 0) {
            float saveProgress = (float)self.albumSaveCompletedCount / (float)self.albumSaveTotalCount;
            if (saveProgress < 0.f) saveProgress = 0.f;
            if (saveProgress > 1.f) saveProgress = 1.f;
            shown = 0.75f + 0.25f * saveProgress;
            status = NSLocalizedString(@"Saving to album", @"Seafile");
        } else {
            // Use already-scaled last progress during unified download phase (DO NOT rescale by 0.75 again)
            float p = self.aggregateLastProgress > 0.f ? self.aggregateLastProgress : 0.f;
            shown = p;
            status = NSLocalizedString(@"Downloading file", @"Seafile");
        }
    } else if (self.isAggregatingDownload) {
        // Non-unified: lastProgress is raw overall progress in [0,1]
        float p = self.aggregateLastProgress > 0.f ? self.aggregateLastProgress : 0.f;
        shown = p;
        status = NSLocalizedString(@"Downloading file", @"Seafile");
    }
    if (shown < 0.f) shown = 0.f;
    if (shown > 1.f) shown = 1.f;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.aggregateOverlayView && (self.aggregateOverlayEnabled || self.unifiedAllMediaProgressActive)) {
            [self ensureAggregateOverlayWithStatus:status initialProgress:shown];
        }
        if (self.aggregateOverlayView) {
            // Heartbeat should never make the bar shorter than current visible length
            float current = self.aggregateProgressView.progress;
            float next = (shown < current ? current : shown);
            self.aggregateProgressView.progress = next;
            self.aggregateStatusLabel.text = status ?: @"";
            if (self.aggregateDetailLabel) {
                self.aggregateDetailLabel.text = [self aggregateProgressDetailString];
            }
            self.aggregateLastDetailUpdateTs = CACurrentMediaTime();
        }
    });
}

- (void)ensureAggregateOverlayWithStatus:(NSString *)status initialProgress:(float)progress
{
    if (!self.aggregateOverlayEnabled && !self.unifiedAllMediaProgressActive && !self.aggregateOverlayView) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.aggregateOverlayView) {
            if (!self.aggregateBackdropView) {
                UIView *container = self.hostVC.view.window ?: UIApplication.sharedApplication.keyWindow ?: self.hostVC.view;
                UIView *backdrop = [[UIView alloc] initWithFrame:container.bounds];
                backdrop.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
                backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                backdrop.userInteractionEnabled = YES;
                self.aggregateBackdropView = backdrop;
                [container addSubview:backdrop];
            }
            CGFloat horizontalMargin = 28.0;
            CGFloat containerWidth = self.aggregateBackdropView.bounds.size.width;
            CGFloat overlayWidth = MAX(160.0, containerWidth - horizontalMargin * 2.0);
            CGFloat overlayHeight = 148.0;
            CGRect frame = CGRectMake((containerWidth - overlayWidth) / 2.0, 0, overlayWidth, overlayHeight);
            
            UIView *overlay = [[UIView alloc] initWithFrame:frame];
            overlay.backgroundColor = [UIColor blackColor]; // fully opaque panel
            overlay.layer.cornerRadius = 14.0;
            overlay.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
            overlay.center = CGPointMake(CGRectGetMidX(self.aggregateBackdropView.bounds), CGRectGetMidY(self.aggregateBackdropView.bounds));
            
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, overlay.bounds.size.width - 32, 22)];
            label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
            label.textColor = [UIColor colorWithWhite:1.0 alpha:0.95];
            label.textAlignment = NSTextAlignmentCenter;
            label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            label.text = status ?: NSLocalizedString(@"Downloading file", @"Seafile");
            [overlay addSubview:label];
            
            UIProgressView *pv = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
            pv.frame = CGRectMake(16, CGRectGetMaxY(label.frame) + 12, overlay.bounds.size.width - 32, 6);
            pv.progressTintColor = [UIColor colorWithWhite:1.0 alpha:0.95];
            pv.trackTintColor = [UIColor colorWithWhite:1.0 alpha:0.25];
            pv.layer.cornerRadius = 3.0;
            pv.clipsToBounds = YES;
            pv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            pv.transform = CGAffineTransformMakeScale(1.0, 1.4);
            pv.progress = (progress < 0.f ? 0.f : (progress > 1.f ? 1.f : progress));
            [overlay addSubview:pv];

            UILabel *detail = [[UILabel alloc] initWithFrame:CGRectMake(16, CGRectGetMaxY(pv.frame) + 10, overlay.bounds.size.width - 32, 18)];
            detail.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
            detail.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
            detail.textAlignment = NSTextAlignmentCenter;
            detail.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            detail.text = [self aggregateProgressDetailString];
            [overlay addSubview:detail];
            
            UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
            cancel.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
            [cancel setTitle:STR_CANCEL forState:UIControlStateNormal];
            [cancel setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            cancel.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
            cancel.layer.cornerRadius = 10.0;
            cancel.clipsToBounds = YES;
            CGFloat btnH = 36.0;
            cancel.frame = CGRectMake(20, CGRectGetMaxY(detail.frame) + 14, overlay.bounds.size.width - 40, btnH);
            cancel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cancel addTarget:self action:@selector(cancelAggregateFlow) forControlEvents:UIControlEventTouchUpInside];
            [overlay addSubview:cancel];
            
            self.aggregateOverlayView = overlay;
            self.aggregateProgressView = pv;
            self.aggregateStatusLabel = label;
            self.aggregateDetailLabel = detail;
            self.aggregateCancelButton = cancel;
            self.aggregateLastDetailUpdateTs = CACurrentMediaTime();
            
            overlay.alpha = 0.0;
            [self.aggregateBackdropView addSubview:overlay];
            [UIView animateWithDuration:0.15 animations:^{
                overlay.alpha = 1.0;
            }];
        } else {
            self.aggregateStatusLabel.text = status ?: self.aggregateStatusLabel.text;
            float clamped = (progress < 0.f ? 0.f : (progress > 1.f ? 1.f : progress));
            self.aggregateProgressView.progress = clamped;
            if (self.aggregateDetailLabel) {
                self.aggregateDetailLabel.text = [self aggregateProgressDetailString];
            }
            self.aggregateLastDetailUpdateTs = CACurrentMediaTime();
        }
    });
}

- (void)startAggregateHUDHeartbeatIfNeeded
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.aggregateHUDHeartbeat && [self.aggregateHUDHeartbeat isValid]) return;
        NSTimer *timer = [NSTimer timerWithTimeInterval:0.5 target:self selector:@selector(pingAggregateHUD) userInfo:nil repeats:YES];
        self.aggregateHUDHeartbeat = timer;
        [[NSRunLoop mainRunLoop] addTimer:self.aggregateHUDHeartbeat forMode:NSRunLoopCommonModes];
    });
}

- (void)cancelAggregateFlow
{
    // Stop album save pipeline
    self.albumSaveInProgress = NO;
    self.unifiedAllMediaProgressActive = NO;
    
    // Cancel all tracked downloads (best-effort)
    if (self.isAggregatingDownload) {
        for (SeafFile *f in self.aggregateFiles) {
            @try { [f cancelDownload]; } @catch (__unused NSException *e) {}
        }
    }
    self.isAggregatingDownload = NO;
    self.aggregateOverlayEnabled = NO;
    [self.aggregateHUDHeartbeat invalidate];
    self.aggregateHUDHeartbeat = nil;
    objc_setAssociatedObject(self, @selector(startAggregateDownloadForFiles:postAction:), nil, OBJC_ASSOCIATION_ASSIGN);
    
    // Dismiss UI
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.aggregateOverlayView) {
            [UIView animateWithDuration:0.15 animations:^{
                self.aggregateOverlayView.alpha = 0.0;
            } completion:^(BOOL finished) {
                [self.aggregateOverlayView removeFromSuperview];
                self.aggregateOverlayView = nil;
                self.aggregateProgressView = nil;
                self.aggregateStatusLabel = nil;
                self.aggregateDetailLabel = nil;
                self.aggregateCancelButton = nil;
                [self.aggregateBackdropView removeFromSuperview];
                self.aggregateBackdropView = nil;
                self.aggregateLastDetailUpdateTs = 0;
            }];
        }
    });
}

@end


