//
//  SeafActionSheet.h
//  seafilePro
//
//  Created by three on 2017/6/14.
//  Copyright © 2017年 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>

/**
 Button Styles
 */
typedef NS_ENUM(NSUInteger, SFActionSheetButtonStyle) {
    SFActionSheetButtonStyleDefault,
    SFActionSheetButtonStyleCancel,
    SFActionSheetButtonStyleRed,
    SFActionSheetButtonStyleBlue
};

/**
 Arrow directions for Sheet on iPad
 */
typedef NS_ENUM(NSUInteger, SFActionSheetArrowDirection) {
    SFActionSheetArrowDirectionLeft,
    SFActionSheetArrowDirectionRight,
    SFActionSheetArrowDirectionTop,
    SFActionSheetArrowDirectionBottom,
};


/**
 section for sheet
 */
@interface SeafActionSheetSection : UIView

/**
 The title of the section.
 */
@property (nonatomic, strong, readonly) UILabel *titleLabel;

/**
 The message of the section.
 */
@property (nonatomic, strong, readonly) UILabel *messageLabel;

/**
 The section buttons are in this array.
 */
@property (nonatomic, strong, readonly) NSArray *buttons;

/**
 The contentView.
 */
@property (nonatomic, strong, readonly) UIView *contentView;

/**
 Convenience initializer for the @c initWithTitle:message:buttonTitles:buttonStyle: initializer.
 */
+ (instancetype)sectionWithTitle:(NSString *)title message:(NSString *)message buttonTitles:(NSArray *)buttonTitles buttonStyle:(SFActionSheetButtonStyle)buttonStyle;

/**
 Initializes the section with buttons.
 @param title The title of the section. (Optional)
 @param message The message of the section. (Optional)
 @param buttonTitles The titles for the buttons in the section.
 @param buttonStyle The style to apply to the buttons. This can be altered later with the @c setButtonStyle:forButtonAtIndex: method
 */
- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message buttonTitles:(NSArray *)buttonTitles buttonStyle:(SFActionSheetButtonStyle)buttonStyle;

/**
 Returns a standard cancel section.
 */
+ (instancetype)cancelSection;

@end

@interface SeafActionSheet : UIView

/**
 The view in which the action sheet is presented.
 */
@property (nonatomic, weak, readonly) UIView *targetView;

/**
 The sections of the action sheet.
 */
@property (nonatomic, strong, readonly) NSArray *sections;

/**
 Insets for the action sheet inside its hosting view.
 */
@property (nonatomic, assign) UIEdgeInsets insets;

/**
 A block that is invoked when a button in any section is pressed.
 */
@property (nonatomic, copy) void (^buttonPressedBlock)(SeafActionSheet *actionSheet, NSIndexPath *indexPath);

/**
 Dismiss the action sheet when tapped outside of the action sheet.
 */
@property (nonatomic, copy) void (^outsidePressBlock)(SeafActionSheet *sheet);

/**
 Convenience initializer for the @c initWithSections: method.
 */
+ (instancetype)actionSheetWithSections:(NSArray *)sections;

/**
 Initializes the action sheet with one or more sections.

 @param sections An array containing all the sections that should be displayed in the action sheet. You must at least provide one section or an exception is thrown.
 */
- (instancetype)initWithSections:(NSArray *)sections;

/**
 Show in view.
 */
- (void)showInView:(UIView *)view animated:(BOOL)animated;

/**
 Show from point.
 */
- (void)showFromPoint:(CGPoint)point inView:(UIView *)view arrowDirection:(SFActionSheetArrowDirection)arrowDirection animated:(BOOL)animated;

/**
 Dismisses the action sheet.
 */
- (void)dismissAnimated:(BOOL)animated;

@end
