//
//  SeafCell.h
//  seafile
//
//  Created by Wang Wei on 1/19/13.
//  Copyright (c) 2013 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SWTableViewCell.h"

@interface SeafCell : SWTableViewCell
@property (strong, nonatomic) IBOutlet UIImageView *imageView;
@property (strong, nonatomic) IBOutlet UILabel *textLabel;
@property (strong, nonatomic) IBOutlet UILabel *detailTextLabel;
@property (strong, nonatomic) IBOutlet UILabel *badgeLabel;
@property (strong, nonatomic) IBOutlet UIImageView *badgeImage;
@property (strong, nonatomic) IBOutlet UIView *cacheStatusView;
@property (strong, nonatomic) IBOutlet UIImageView *downloadStatusImageView;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *cacheStatusWidthConstraint;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *downloadingIndicator;

@property (strong, nonatomic) IBOutlet UIProgressView *progressView;

- (void)reset;

@end
