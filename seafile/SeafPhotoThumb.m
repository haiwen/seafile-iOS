//
//  SeafThumb.m
//  seafilePro
//
//  Created by Wang Wei on 11/21/15.
//  Copyright © 2015 Seafile. All rights reserved.
//

#import "SeafPhotoThumb.h"
#import "SeafFile.h"
#import "SeafDataTaskManager.h"
#import "Debug.h"

@interface SeafPhotoThumb ()

@property BOOL loadingInProgress;// Flag indicating whether a loading operation is currently in progress
@end

@implementation SeafPhotoThumb

@synthesize underlyingImage = _underlyingImage; // synth property from protocol

// Getter for underlyingImage. If image already loaded, return it, otherwise, attempt to generate it.
- (UIImage *)underlyingImage {
    return [self.file thumb];
}

// Begins the process of loading the underlying image and posts a notification when the image is loaded or an error occurs.
- (void)loadUnderlyingImageAndNotify {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    if (_loadingInProgress) return;
    _loadingInProgress = YES;
    @try {
        if (_underlyingImage) {
            [self imageLoadingComplete];
            return;
        }
        _underlyingImage = [self.file thumb];
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
    if ([self.file isKindOfClass:[SeafFile class]]) {
        SeafFile *sfile = (SeafFile *)self.file;
        [sfile setThumbCompleteBlock:^(BOOL ret) {
            self.underlyingImage = [self.file thumb];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self imageLoadingComplete];
            });
        }];
        [SeafDataTaskManager.sharedObject addThumbTask:self];
    }
}


// Release if we can get it again from path or url
- (void)unloadUnderlyingImage
{
    _loadingInProgress = NO;
    self.underlyingImage = nil;
}

// Notifies that the image has been fully loaded or an error has occurred
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
