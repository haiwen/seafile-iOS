//
//  SeafRepliesHeaderView.m
//  seafilePro
//
//  Created by Wang Wei on 4/10/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import "SeafRepliesHeaderView.h"
#import "SeafMessage.h"
#import "UIColor+JSMessagesView.h"

@implementation SeafRepliesHeaderView
@synthesize timestamp = _timestamp;
@synthesize btn = _btn;

- (void)setup
{
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.frame.size.width - 100, REPLIES_HEADER_HEIGHT)];
    label.autoresizingMask =  UIViewAutoresizingFlexibleWidth;
    label.backgroundColor = [UIColor clearColor];
    label.textAlignment = NSTextAlignmentLeft;
    label.textColor = [UIColor js_messagesTimestampColorClassic];
    label.shadowColor = [UIColor whiteColor];
    label.shadowOffset = CGSizeMake(0.0f, 1.0f);
    label.font = [UIFont boldSystemFontOfSize:12.0f];
    [self addSubview:label];
    [self bringSubviewToFront:label];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.showsTouchWhenHighlighted = YES;
    [btn setImage:[UIImage imageNamed:@"addmsg2"] forState:UIControlStateNormal];
    [self addSubview:btn];
    [self bringSubviewToFront:btn];
    _timestamp = label;
    _btn = btn;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.frame = frame;
        [self setup];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.btn.frame = CGRectMake([UIScreen mainScreen].applicationFrame.size.width * 0.70f, 2, REPLIES_HEADER_HEIGHT-4, REPLIES_HEADER_HEIGHT-4);
}

@end
