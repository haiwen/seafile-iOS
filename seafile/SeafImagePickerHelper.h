//
//  SeafImagePickerHelper.h
//  seafile
//
//  Unified wrapper around PHPickerViewController. Presents the system picker
//  without requiring Photo Library permission up front. Resolves PHAsset when
//  the library is accessible (Live Photo / existing upload pipeline); otherwise
//  materializes NSItemProvider file representations into a temp directory.
//

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, SeafImagePickerMediaType) {
    SeafImagePickerMediaTypeImage = 0,
    SeafImagePickerMediaTypeVideo,
    SeafImagePickerMediaTypeAny,
};

@class SeafImagePickerHelper;

@protocol SeafImagePickerHelperDelegate <NSObject>
@optional
/// Preferred single delivery for a picker session that may contain both PHAssets
/// and provider-materialized file URLs. When implemented, the separate assets /
/// fileURLs callbacks below are not invoked for that session.
- (void)imagePickerHelper:(SeafImagePickerHelper *)helper
    didFinishPickingAssets:(NSArray<PHAsset *> *)assets
                  fileURLs:(NSArray<NSURL *> *)fileURLs;

/// PHAssets resolved from picker results (library-accessible selections).
/// Not called when the combined assets+fileURLs method is implemented.
- (void)imagePickerHelper:(SeafImagePickerHelper *)helper
    didFinishPickingAssets:(NSArray<PHAsset *> *)assets;

/// Local file URLs materialized from NSItemProvider (copied into a temp dir).
/// Caller owns cleanup / upload; URLs are file:// paths under a temp directory.
/// Not called when the combined assets+fileURLs method is implemented.
- (void)imagePickerHelper:(SeafImagePickerHelper *)helper
    didFinishPickingFileURLs:(NSArray<NSURL *> *)fileURLs;

/// One or more selected items could not be loaded. May be called alone (total
/// failure) or after partial success callbacks.
- (void)imagePickerHelper:(SeafImagePickerHelper *)helper
        didFailWithMessage:(NSString *)message;

/// User cancelled or confirmed with an empty selection.
- (void)imagePickerHelperDidCancel:(SeafImagePickerHelper *)helper;
@end

@interface SeafImagePickerHelper : NSObject

@property (nonatomic, weak) id<SeafImagePickerHelperDelegate> delegate;

/// Allow multiple selection. Default YES.
@property (nonatomic, assign) BOOL allowsMultipleSelection;

/// Media type filter. Default SeafImagePickerMediaTypeImage.
@property (nonatomic, assign) SeafImagePickerMediaType mediaType;

/// Maximum number of selectable items. 0 = unlimited. Default 0.
@property (nonatomic, assign) NSUInteger maximumNumberOfSelection;

/// Present the system photo picker from the given view controller.
/// @param vc        The presenting view controller.
/// @param barItem   Optional bar button item for iPad popover anchoring.
/// @param sourceView Optional source view for iPad popover anchoring (used when barItem is nil).
- (void)presentFromViewController:(UIViewController *)vc
                    barButtonItem:(UIBarButtonItem * _Nullable)barItem
                       sourceView:(UIView * _Nullable)sourceView;

@end

NS_ASSUME_NONNULL_END
