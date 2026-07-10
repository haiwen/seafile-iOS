//
//  SeafShareDestCell.h
//  SeafShare
//
//  Lightweight destination-style cell for Share Extension.
//  Layout metrics match SeafCell (used by the Starred tab / main-app lists).
//

#import <UIKit/UIKit.h>

@interface SeafShareDestCell : UITableViewCell

@property (nonatomic, strong, readonly) UIImageView *iconView;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *subtitleLabel;
@property (nonatomic, strong, readonly) UIImageView *checkboxView;

/// Updates checkbox to match main-app SeafCell selection style (ic_checkbox_*).
- (void)updateCheckboxImageForSelected:(BOOL)selected;

@end
