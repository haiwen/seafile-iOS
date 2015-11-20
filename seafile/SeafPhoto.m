//
//  SeafPhoto.m
//  seafilePro
//
//  Created by Wang Wei on 10/17/15.
//  Copyright © 2015 Seafile. All rights reserved.
//
#import "SeafPhoto.h"
#import "Debug.h"

@interface SeafPhoto ()

@property BOOL loadingInProgress;
@end


@implementation SeafPhoto

@synthesize underlyingImage = _underlyingImage; // synth property from protocol


- (id)initWithSeafPreviewIem:(id<SeafPreView>)file {
    if ((self = [super init])) {
        _file = file;
    }
    return self;
}

- (void)loadCache
{
    @synchronized(_file) {
        if (!_underlyingImage && [_file hasCache]) {
            self.underlyingImage = _file.image;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self imageLoadingComplete];
            });
        }
    }
}

- (UIImage *)underlyingImage {
    return _underlyingImage;
}

- (void)loadUnderlyingImageAndNotify {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    if (_loadingInProgress) return;
    _loadingInProgress = YES;
    @try {
        if (_underlyingImage) {
            [self imageLoadingComplete];
        } else if (!_underlyingImage && [_file hasCache]) {
            [self performSelectorInBackground:@selector(loadCache) withObject:nil];
        } else {
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
    [_file load:nil force: false];
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

- (void)setProgress: (float)progress
{
    NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithFloat:progress], @"progress",
                          self, @"photo", nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_PROGRESS_NOTIFICATION object:dict];
}
- (void)complete:(BOOL)updated error:(NSError *)error
{
    if (error) {
        Debug("failed to download image: %@", error);
    }
    self.underlyingImage = _file.image;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self imageLoadingComplete];
    });
}

@end
