//
//  SeafLoadingView.m
//  seafilePro
//
//  Created by Seafile Ltd.
//  Copyright (c) 2024 Seafile Ltd. All rights reserved.
//

#import "SeafLoadingView.h"

@interface SeafLoadingView()

@property (strong, nonatomic) UIActivityIndicatorView *activityIndicator;

@end

@implementation SeafLoadingView

+ (instancetype)loadingViewWithParentView:(UIView *)parentView {
    SeafLoadingView *loadingView = [[SeafLoadingView alloc] initWithFrame:CGRectMake(0, 0, parentView.bounds.size.width, parentView.bounds.size.height)];
    [loadingView setupActivityIndicator];
    return loadingView;
}

- (void)setupActivityIndicator {
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.activityIndicator.color = [UIColor darkTextColor];
    self.activityIndicator.hidesWhenStopped = YES;
    [self addSubview:self.activityIndicator];
    
    // Center the activity indicator in the loading view
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];
}

- (void)showInView:(UIView *)view {
    self.frame = view.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:self];
    [self.activityIndicator startAnimating];
    
    // Ensure we're above all other views
    [view bringSubviewToFront:self];
}

- (void)dismiss {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.activityIndicator stopAnimating];
        [self removeFromSuperview];
    });
}

- (void)updatePosition {
    if (self.superview) {
        self.frame = self.superview.bounds;
    }
}

@end 
