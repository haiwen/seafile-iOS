#import "SeafPGThumbnailCellViewModel.h"
#import "SeafFile.h"
#import "SeafUploadFile.h"
#import "SeafDataTaskManager.h"
#import "SeafPhotoThumb.h"
#import "Debug.h"

@interface SeafPGThumbnailCellViewModel ()
@property (nonatomic, strong, readwrite, nullable) UIImage *thumbnailImage;
@property (nonatomic, assign, readwrite) BOOL isLoading;
@property (nonatomic, weak) SeafFile *currentSeafFileForThumbLoading; // Keep track of the SeafFile being loaded
@end

@implementation SeafPGThumbnailCellViewModel

- (instancetype)initWithPreviewItem:(id<SeafPreView>)previewItem {
    self = [super init];
    if (self) {
        _previewItem = previewItem;
        // Initial state based on the item
        [self updateStateFromPreviewItem];
    }
    return self;
}

- (void)updateStateFromPreviewItem {
    if ([self.previewItem isKindOfClass:[SeafFile class]]) {
        SeafFile *seafFile = (SeafFile *)self.previewItem;
        UIImage *thumb = [seafFile thumb];
        if (thumb) {
            self.thumbnailImage = thumb;
            self.isLoading = NO;
        } else {
            // If it's an image file and no thumb, it might be loading or need to load
            self.thumbnailImage = [UIImage imageNamed:@"gallery_placeholder.png"]; // Or your preferred placeholder
            self.isLoading = [seafFile isImageFile]; // isLoading is true if it's an image and needs loading
        }
    } else if ([self.previewItem isKindOfClass:[SeafUploadFile class]]) {
        SeafUploadFile *uploadFile = (SeafUploadFile *)self.previewItem;
        UIImage *thumb = [uploadFile thumb];
        if (thumb) {
            self.thumbnailImage = thumb;
            self.isLoading = NO;
        } else {
            self.thumbnailImage = [UIImage imageNamed:@"gallery_placeholder.png"];
            self.isLoading = YES; // Assume upload items might need to generate/load thumbs
        }
    } else {
        self.thumbnailImage = [UIImage imageNamed:@"gallery_failed.png"];
        self.isLoading = NO;
    }
}

- (void)loadThumbnailIfNeeded {
    if (!self.previewItem) return;

    // If already has an image (and not a placeholder, or if loading is false)
    if (self.thumbnailImage && ![self.thumbnailImage isEqual:[UIImage imageNamed:@"gallery_placeholder.png"]] && !self.isLoading) {
        // Potentially trigger onUpdate if initial state was sufficient
        if (self.onUpdate) {
            self.onUpdate();
        }
        return;
    }

    if ([self.previewItem isKindOfClass:[SeafFile class]]) {
        SeafFile *seafFile = (SeafFile *)self.previewItem;
        self.currentSeafFileForThumbLoading = seafFile; // Store for callback

        UIImage *thumb = [seafFile thumb];
        if (thumb) {
            self.thumbnailImage = thumb;
            self.isLoading = NO;
            if (self.onUpdate) {
                self.onUpdate();
            }
            return;
        }

        if ([seafFile isImageFile]) {
            self.isLoading = YES;
            // Ensure onUpdate is called for initial loading state if it wasn't already.
            if (self.onUpdate) {
                 self.onUpdate();
            }

            __weak typeof(self) weakSelf = self;
            // Important: Use a new block each time, don't rely on a single stored block if this method can be called multiple times.
            [seafFile setThumbCompleteBlock:^(BOOL success) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf || strongSelf.currentSeafFileForThumbLoading != seafFile) {
                    // ViewModel might have been reused for another item, or this is an old callback.
                    return;
                }

                // Perform UI updates on the main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (success) {
                        UIImage *currentThumbImage = [seafFile thumb];
                        if (currentThumbImage) {
                            strongSelf.thumbnailImage = currentThumbImage;
                            strongSelf.isLoading = NO;
                        } else {
                            // Treat this as a failure to prevent a loop.
                            Debug(@"[VM] Thumb task for %@ reported success, but image is not loadable. Displaying error.", seafFile.name);
                            strongSelf.thumbnailImage = [UIImage imageNamed:@"gallery_failed.png"];
                            strongSelf.isLoading = NO;
                        }
                    } else {
                        Debug(@"[VM] Thumb task for %@ failed.", seafFile.name);
                        strongSelf.thumbnailImage = [UIImage imageNamed:@"gallery_failed.png"];
                        strongSelf.isLoading = NO;
                    }
                    if (strongSelf.onUpdate) {
                        strongSelf.onUpdate();
                    }
                });
            }];

            SeafPhotoThumb *thumbTask = [[SeafPhotoThumb alloc] initWithSeafFile:seafFile];
            [[SeafDataTaskManager sharedObject] addThumbTask:thumbTask];
        } else {
            // Not an image file
            self.thumbnailImage = [UIImage imageNamed:@"gallery_failed.png"];
            self.isLoading = NO;
            if (self.onUpdate) {
                self.onUpdate();
            }
        }
    } else if ([self.previewItem isKindOfClass:[SeafUploadFile class]]) {
        // For SeafUploadFile, the thumb is usually generated from the asset directly.
        // Assuming a synchronous or quickly available thumb for simplicity here.
        // If it were async, similar block-based callback logic would be needed.
        SeafUploadFile *uploadFile = (SeafUploadFile *)self.previewItem;
        UIImage *thumb = [uploadFile thumb];
        if (thumb) {
            self.thumbnailImage = thumb;
            self.isLoading = NO;
        } else {
            self.thumbnailImage = [UIImage imageNamed:@"gallery_placeholder.png"]; // Or specific upload placeholder
            self.isLoading = YES; // Or NO if we know it won't load further
        }
        if (self.onUpdate) {
            self.onUpdate();
        }
    }
}

- (void)cancelThumbnailLoad {
    if (self.currentSeafFileForThumbLoading) {
        // Clear the block to prevent old callbacks from firing
        [self.currentSeafFileForThumbLoading setThumbCompleteBlock:nil];
        // We don't directly remove from SeafDataTaskManager here, as tasks are typically identified by more than just the SeafFile object.
        // The SeafPhotoThumb task itself might not be easily removable without more complex tracking.
        Debug(@"[VM] Cleared thumbCompleteBlock for %@ during cancel.", self.currentSeafFileForThumbLoading.name);
        self.currentSeafFileForThumbLoading = nil;
    }
    // If we were in a loading state, and it's cancelled, we might want to revert to a placeholder or stop the indicator
    if (self.isLoading) {
        self.isLoading = NO; // Stop showing loading
        // self.thumbnailImage = [UIImage imageNamed:@"gallery_placeholder.png"]; // Optionally reset image
        if (self.onUpdate) {
            self.onUpdate();
        }
    }
}

- (void)dealloc {
    [self cancelThumbnailLoad];
}

@end 
