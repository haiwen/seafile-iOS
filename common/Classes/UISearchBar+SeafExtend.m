//
//  UISearchBar+SeafExtend.m
//  seafileApp
//
//  Created by three on 2019/8/25.
//  Copyright © 2019 Seafile. All rights reserved.
//

#import "UISearchBar+SeafExtend.h"
#import "objc/runtime.h"

@implementation UISearchBar (SeafExtend)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method originMethod = class_getInstanceMethod([self class], @selector(layoutSubviews));
        Method customMethod = class_getInstanceMethod([self class], @selector(seaf_layoutSubviews));
        
        BOOL addSucc = class_addMethod([self class], @selector(layoutSubviews), method_getImplementation(customMethod), method_getTypeEncoding(customMethod));
        if (addSucc) {
            class_replaceMethod([self class], @selector(seaf_layoutSubviews), method_getImplementation(originMethod), method_getTypeEncoding(originMethod));
        } else {
            method_exchangeImplementations(originMethod, customMethod);
        }
    });
}

- (void)seaf_layoutSubviews {
    [self seaf_layoutSubviews];
    if (@available(iOS 13.0, *)) {
        //fix searchbar's frame
        UIView *backgroundView = [self performSelector:NSSelectorFromString(@"_backgroundView")];
        if (backgroundView) {
            CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
            CGRect frame = backgroundView.frame;
            frame.origin.y = -statusBarHeight;
            frame.size.height = frame.size.height + statusBarHeight;
            backgroundView.frame = frame;
        }
    }
}

@end
