//
//  SeafHeaderView.h
//  seafileApp
//
//  Created by henry on 2025/3/25.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SeafHeaderView : UITableViewHeaderFooterView

@property (nonatomic, copy) void (^toggleAction)(NSInteger section);

- (instancetype)initWithSection:(NSInteger)section
                          title:(NSString *)title
                      expanded:(BOOL)isExpanded;

+ (CGFloat)headerHeight;
- (void)setExpanded:(BOOL)isExpanded animated:(BOOL)animated;

@end
