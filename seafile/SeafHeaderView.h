//
//  SeafHeaderView.h
//  seafileApp
//
//  Created by henry on 2025/3/25.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SeafHeaderView : UIView

@property (nonatomic, assign) NSInteger section;
// Callback when the toggle button is tapped, passing the current section
@property (nonatomic, copy) void (^toggleAction)(NSInteger section);
// Callback when the entire header is tapped, passing the current section
@property (nonatomic, copy) void (^tapAction)(NSInteger section);

/**
 Initialize a SeafHeaderView

 @param section The section to which the header belongs
 @param title The text to be displayed on the header
 @param isExpanded Whether the header is expanded
 @return SeafHeaderView instance
 */
- (instancetype)initWithSection:(NSInteger)section
                          title:(NSString *)title
                      expanded:(BOOL)isExpanded;

/**
 Update the arrow display based on the expanded state

 @param isExpanded YES means expanded
 @param animated Whether to update with animation
 */
- (void)setExpanded:(BOOL)isExpanded animated:(BOOL)animated;

@end
