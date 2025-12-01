//
//  SeafSdocEditorToolbar.h
//  seafilePro
//
//  Created on 2025/12/05.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SeafSdocEditorToolbarDelegate <NSObject>

- (void)editorToolbarDidTapUndo;
- (void)editorToolbarDidTapRedo;
- (void)editorToolbarDidTapStyle:(UIButton *)sender;
- (void)editorToolbarDidTapUnorderedList;
- (void)editorToolbarDidTapOrderedList;
- (void)editorToolbarDidTapCheckList;
- (void)editorToolbarDidTapKeyboard;

@end

@interface SeafSdocEditorToolbar : UIView

@property (nonatomic, weak) id<SeafSdocEditorToolbarDelegate> delegate;

/// Update toolbar state with style model from JS
/// @param model Dictionary containing "type" key for current style
- (void)updateWithStyleModel:(NSDictionary *)model;

/// Update undo/redo button states
/// @param canUndo Whether undo is available
/// @param canRedo Whether redo is available
- (void)updateUndoEnabled:(BOOL)canUndo redoEnabled:(BOOL)canRedo;

/// Get the style button for popover anchor
- (UIButton *)styleButton;

@end

NS_ASSUME_NONNULL_END

