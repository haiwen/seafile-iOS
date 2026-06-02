//  SeafTagSelectorViewController.h
//  Custom tag multi-select bottom sheet, aligned with Android TagSelectorFragment.
//  Displays a list of tags with color indicator dots and selection checkmarks.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Completion block: returns list of selected tags (each dict has id, name, color)
typedef void (^SeafTagSelectorCompletion)(NSString *key, NSArray<NSDictionary *> *selectedTags);

@interface SeafTagSelectorViewController : UIViewController

/// @param key The metadata key (e.g. "_tags")
/// @param allTags All available tags from tagList (each has _id, _tag_name, _tag_color)
/// @param selectedTags Currently selected tags (each dict has id, name, color)
/// @param completion Called when user taps Done
- (instancetype)initWithKey:(NSString *)key
                    allTags:(NSArray<NSDictionary *> *)allTags
               selectedTags:(NSArray<NSDictionary *> *)selectedTags
                 completion:(SeafTagSelectorCompletion)completion;

@end

NS_ASSUME_NONNULL_END
