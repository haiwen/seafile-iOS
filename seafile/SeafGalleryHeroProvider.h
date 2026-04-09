//
//  SeafGalleryHeroProvider.h
//  seafileApp
//
//  Protocol implemented by view controllers that present
//  SeafPhotoGalleryViewController, allowing the gallery's custom
//  dismiss transition to perform a Hero (zoom-back-to-thumbnail)
//  animation that targets the source cell the photo originated from.
//

#import <UIKit/UIKit.h>

@protocol SeafPreView;

NS_ASSUME_NONNULL_BEGIN

@protocol SeafGalleryHeroProvider <NSObject>

/// Returns the on-screen view (typically a UIImageView inside a list cell)
/// that visually represents the given item. Return nil if no such view
/// exists in the presenter — the gallery will fall back to a plain
/// shrink-and-fade dismissal.
- (nullable UIView *)gallerySourceViewForItem:(id<SeafPreView>)item;

/// Returns the rectangle of the source view in window coordinates.
/// Implementations should call `[sourceView convertRect:sourceView.bounds toView:nil]`.
/// Return CGRectZero when no source view is available.
- (CGRect)gallerySourceFrameInWindowForItem:(id<SeafPreView>)item;

/// Called once before the dismiss transition starts, giving the presenter
/// an opportunity to scroll the source cell into the visible area so the
/// returned source view/frame are valid (otherwise dequeued cells may be nil).
/// Implementations should perform any required scroll synchronously and
/// call `[self.view layoutIfNeeded]` so subsequent rect lookups are accurate.
- (void)galleryWillDismissToItem:(id<SeafPreView>)item;

@optional
/// Called once the gallery has finished its dismiss animation. The
/// presenter typically uses this to refresh per-row state (download
/// indicators, starred flags) since `viewWillAppear:` does NOT fire
/// when dismissing a `UIModalPresentationOverFullScreen` presentation —
/// which is the style the gallery uses so the Hero animator can fade it
/// over the still-visible source list.
- (void)galleryDidDismissToItem:(id<SeafPreView>)item;

@end

NS_ASSUME_NONNULL_END
