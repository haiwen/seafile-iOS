//
//  SeafPhotoPageContainer.m
//  seafileApp
//
//  Created by henry on 2026/4/21.
//  Copyright © 2026 Seafile. All rights reserved.
//

#import "SeafPhotoPageContainer.h"

@implementation SeafPhotoPageContainer

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _pageIndex = NSNotFound;
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    return self;
}

@end
