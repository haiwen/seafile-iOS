//
//  SeafErrorPlaceholderView.m
//  seafileApp
//
//  Created by Henry on 2025/06/05.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import "SeafErrorPlaceholderView.h"

@interface SeafErrorPlaceholderView ()

@property (nonatomic, strong) UIImageView *errorIconImageView;
@property (nonatomic, strong) UILabel *errorLabel;

@end

@implementation SeafErrorPlaceholderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        // Create the smaller error image view
        UIImage *errorIconImage = [UIImage imageNamed:@"gallery_failed.png"];
        _errorIconImageView = [[UIImageView alloc] initWithImage:errorIconImage];
        _errorIconImageView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_errorIconImageView];

        // Create the error label
        _errorLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        NSString *fullText = NSLocalizedString(@"Load failed, tap to retry", @"Seafile");
        NSString *retryText = NSLocalizedString(@"tap to retry", @"Seafile");

        NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:fullText];
        NSRange fullRange = NSMakeRange(0, fullText.length);
        NSRange retryTapRange = [fullText rangeOfString:retryText];

        UIFont *defaultFont = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
        UIColor *defaultTextColor = [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:1.0]; // A medium gray

        [attributedString addAttribute:NSFontAttributeName value:defaultFont range:fullRange];
        [attributedString addAttribute:NSForegroundColorAttributeName value:defaultTextColor range:fullRange];

        if (retryTapRange.location != NSNotFound) {
            UIColor *retryTextColor = [UIColor colorWithRed:0.95 green:0.6 blue:0.2 alpha:1.0]; // Orange color
            [attributedString addAttribute:NSForegroundColorAttributeName value:retryTextColor range:retryTapRange];
            [attributedString addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:retryTapRange];
        }

        _errorLabel.attributedText = attributedString;
        _errorLabel.textAlignment = NSTextAlignmentCenter;
        _errorLabel.numberOfLines = 0;
        [self addSubview:_errorLabel];

        // Add tap gesture for retry
        UITapGestureRecognizer *retryTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleRetryTap)];
        [self addGestureRecognizer:retryTapGesture];
        self.userInteractionEnabled = YES;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat iconSize = 130.0;
    self.errorIconImageView.frame = CGRectMake(0, 0, iconSize, iconSize); // Initial size

    [self.errorLabel sizeToFit]; // Calculate label size based on current text/attributes

    CGFloat spacingBetweenIconAndLabel = 8.0;
    CGFloat totalContentHeight = self.errorIconImageView.frame.size.height + spacingBetweenIconAndLabel + self.errorLabel.frame.size.height;

    // Center vertically, adjusted slightly upwards
    CGFloat startY = (self.bounds.size.height - totalContentHeight) / 2.0 - 25.0;
    
    self.errorIconImageView.frame = CGRectMake(
        (self.bounds.size.width - self.errorIconImageView.frame.size.width) / 2.0,
        startY,
        self.errorIconImageView.frame.size.width,
        self.errorIconImageView.frame.size.height
    );

    // Ensure the label width doesn't exceed the view width with some padding
    CGFloat maxLabelWidth = self.bounds.size.width - 40; // 20px padding on each side
    CGRect currentLabelFrame = self.errorLabel.frame;
    currentLabelFrame.size.width = MIN(currentLabelFrame.size.width, maxLabelWidth);
    
    self.errorLabel.frame = CGRectMake(
        (self.bounds.size.width - currentLabelFrame.size.width) / 2.0,
        startY + self.errorIconImageView.frame.size.height + spacingBetweenIconAndLabel,
        currentLabelFrame.size.width,
        currentLabelFrame.size.height
    );
}

- (void)handleRetryTap {
    if (self.retryActionBlock) {
        self.retryActionBlock();
    }
}

@end 
