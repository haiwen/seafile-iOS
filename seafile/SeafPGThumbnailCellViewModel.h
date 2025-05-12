#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "SeafPreView.h"

NS_ASSUME_NONNULL_BEGIN

@interface SeafPGThumbnailCellViewModel : NSObject

@property (nonatomic, strong, readonly, nullable) UIImage *thumbnailImage;
@property (nonatomic, assign, readonly) BOOL isLoading;
@property (nonatomic, strong, readonly) id<SeafPreView> previewItem;

/// Called when the thumbnailImage or isLoading state has been updated, especially after an async load.
@property (nonatomic, copy, nullable) void (^onUpdate)(void);

- (instancetype)initWithPreviewItem:(id<SeafPreView>)previewItem;

/// Triggers the loading of the thumbnail data if it's not already available.
/// The `onUpdate` block will be called when data changes.
- (void)loadThumbnailIfNeeded;

/// Call this to cancel any ongoing thumbnail loading.
- (void)cancelThumbnailLoad;

@end

NS_ASSUME_NONNULL_END 
