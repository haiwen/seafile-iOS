//
//  SeafImagePickerHelper.h
//  seafile
//
//  Unified wrapper around QBImagePickerController for photo-library access.
//  Encapsulates permission checks, iPad popover, Limited-access handling,
//  and Seafile theme styling so every call-site behaves identically.
//

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import "QBImagePickerController.h"

NS_ASSUME_NONNULL_BEGIN

@class SeafImagePickerHelper;

@protocol SeafImagePickerHelperDelegate <NSObject>
/// Called when the user finishes picking one or more PHAssets.
- (void)imagePickerHelper:(SeafImagePickerHelper *)helper
    didFinishPickingAssets:(NSArray<PHAsset *> *)assets;
@optional
/// Called when the user cancels the picker.
- (void)imagePickerHelperDidCancel:(SeafImagePickerHelper *)helper;
@end

@interface SeafImagePickerHelper : NSObject <QBImagePickerControllerDelegate>

@property (nonatomic, weak) id<SeafImagePickerHelperDelegate> delegate;

/// Allow multiple selection. Default YES.
@property (nonatomic, assign) BOOL allowsMultipleSelection;

/// Media type filter. Default QBImagePickerMediaTypeImage.
@property (nonatomic, assign) QBImagePickerMediaType mediaType;

/// Maximum number of selectable items. 0 = unlimited. Default 0.
@property (nonatomic, assign) NSUInteger maximumNumberOfSelection;

/// Present the QBImagePicker from the given view controller.
/// @param vc        The presenting view controller.
/// @param barItem   Optional bar button item for iPad popover anchoring.
/// @param sourceView Optional source view for iPad popover anchoring (used when barItem is nil).
- (void)presentFromViewController:(UIViewController *)vc
                    barButtonItem:(UIBarButtonItem * _Nullable)barItem
                       sourceView:(UIView * _Nullable)sourceView;

@end

NS_ASSUME_NONNULL_END
