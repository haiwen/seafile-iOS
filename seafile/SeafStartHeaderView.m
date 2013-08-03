//
//  SeafStartHeaderView.m
//  seafile
//
//  Created by Wang Wei on 1/13/13.
//  Copyright (c) 2013 Seafile Ltd. All rights reserved.
//

#import "SeafStartHeaderView.h"

@implementation SeafStartHeaderView

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];
    for (UIView *v in self.subviews) {
        v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin| UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin;
    }
    return self;
}

@end


@implementation SeafStartFooterView

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];
    for (UIView *v in self.subviews) {
        v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin| UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin;
    }
    return self;
}

@end
