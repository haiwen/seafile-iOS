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
 The section buttons are in this array.
 */
@property (nonatomic, strong, readonly) NSArray *buttons;

/**
 Convenience initializer for the initWithTitle:message:buttonTitles:buttonStyle: initializer.
 */
+(instancetype)sectionWithButtonTitles:(NSArray *)buttonTitles buttonStyle:(SFActionSheetButtonStyle)buttonStyle;

/**
 Initializes the section with buttons.
 @param buttonTitles The titles for the buttons in the section.
 @param buttonStyle The style to apply to the buttons. This can be altered later with the @c setButtonStyle:forButtonAtIndex: method
 */
- (instancetype)initWithButtonTitles:(NSArray *)buttonTitles buttonStyle:(SFActionSheetButtonStyle)buttonStyle;

/**
 Returns a standard cancel section.
 */
+ (instancetype)cancelSection;

@end

@interface SeafActionSheet : UIView

/**
 target viewcontroller
 */
@property (nonatomic, weak) UIViewController *targetVC;

/**
 A block that is invoked when a button in any section is pressed.
 */
@property (nonatomic, copy) void (^buttonPressedBlock)(SeafActionSheet *actionSheet, NSIndexPath *indexPath);

/**
 Convenience initializer

 @param titles titles
 @return action sheet
 */
+ (instancetype)actionSheetWithTitles:(NSArray *)titles;

/**
 Show from view.
 */
- (void)showFromView:(id)view;

/**
 Dismisses the action sheet.
 */
- (void)dismissAnimated:(BOOL)animated;

@end
