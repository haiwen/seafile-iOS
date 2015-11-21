//
//  SeafThumb.m
//  seafilePro
//
//  Created by Wang Wei on 11/21/15.
//  Copyright © 2015 Seafile. All rights reserved.
//

#import "SeafThumb.h"
#import "SeafFile.h"
#import "Debug.h"

@interface SeafThumb ()

@property BOOL loadingInProgress;
@end

@implementation SeafThumb

@synthesize underlyingImage = _underlyingImage; // synth property from protocol


- (id)initWithSeafPreviewIem:(id<SeafPreView>)file {
    if ((self = [super init])) {
        _file = file;
    }
    return self;
}

- (UIImage *)underlyingImage {
    return [_file thumb];
}

- (void)loadUnderlyingImageAndNotify {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    if (_loadingInProgress) return;
    _loadingInProgress = YES;
    @try {
        if (_underlyingImage) {
            [self imageLoadingComplete];
            return;
        }
        _underlyingImage = [_file thumb];
        if (!_underlyingImage) {
            [self performLoadUnderlyingImageAndNotify];
        }
    }
    @catch (NSException *exception) {
        self.underlyingImage = nil;
        _loadingInProgress = NO;
        [self imageLoadingComplete];
    }
    @finally {
    }
}

// Set the underlyingImage
- (void)performLoadUnderlyingImageAndNotify {
    if ([_file isKindOfClass:[SeafFile class]]) {
        SeafFile *sfile = (SeafFile *)_file;
        [sfile setThumbCompleteBlock:^(BOOL ret) {
            self.underlyingImage = [_file thumb];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self imageLoadingComplete];
            });
        }];
        [sfile downloadThumb];
    }
}


// Release if we can get it again from path or url
- (void)unloadUnderlyingImage
{
    _loadingInProgress = NO;
    self.underlyingImage = nil;
}

- (void)imageLoadingComplete {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    // Complete so notify
    _loadingInProgress = NO;
    // Notify on next run loop
    [self postCompleteNotification];
}

- (void)postCompleteNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_LOADING_DID_END_NOTIFICATION
                                                        object:self];
}

- (void)cancelAnyLoading
{
}

@end
