//  SeafSdocOptionSelectorViewController.h
//  Generic multi-select checkmark list presented as a bottom sheet.
//  Used by the profile editor for multiple-select and collaborator fields
//  (align Android: CollaboratorSelectorFragment / SupportMetadataCheckGroup).

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SeafSdocOptionSelectorCompletion)(NSArray<NSString *> *selectedIds);

@interface SeafSdocOptionSelectorViewController : UIViewController

/// items: array of @{ @"id": NSString, @"name": NSString } — "name" is displayed,
/// selection is tracked by "id". Selected ids are returned in items order.
- (instancetype)initWithTitle:(NSString *)title
                        items:(NSArray<NSDictionary *> *)items
                  selectedIds:(NSArray<NSString *> *)selectedIds
                   completion:(SeafSdocOptionSelectorCompletion)completion;

@end

NS_ASSUME_NONNULL_END
