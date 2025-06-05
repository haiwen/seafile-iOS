//
//  SeafPhotoGalleryViewController.h
//  seafileApp
//
//  Created by henry on 2025/4/17.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafFile.h"
#import "SeafPGThumbnailCellViewModel.h"
#import "SeafPhotoContentViewController.h"

@interface SeafPhotoGalleryViewController : UIViewController <SeafDentryDelegate, SeafPhotoContentDelegate>

// Initialization method using SeafFile object
- (instancetype)initWithPhotos:(NSArray<id<SeafPreView>> *)files
                   currentItem:(id<SeafPreView>)currentItem
                        master:(UIViewController<SeafDentryDelegate> *)masterVC;

// Track the range of loaded images
@property (nonatomic, readonly) NSRange loadedImagesRange;

// Expose UI Components as readonly properties
@property (nonatomic, strong, readonly, nullable) UICollectionView *thumbnailCollection;
@property (nonatomic, strong, readonly, nullable) UIView *toolbarView;
@property (nonatomic, strong, readonly, nullable) UIView *leftThumbnailOverlay;
@property (nonatomic, strong, readonly, nullable) UIView *rightThumbnailOverlay;

// Expose internal state for specific use cases
@property (nonatomic, strong, readonly, nullable) NSArray<SeafPhotoContentViewController *> *photoViewControllers;
@property (nonatomic, readonly) NSUInteger currentIndex;

@end

@interface SeafPhotoGalleryViewController () <UIPageViewControllerDataSource,
                                             UIPageViewControllerDelegate,
                                             UICollectionViewDataSource,
                                             UICollectionViewDelegate,
                                             UICollectionViewDelegateFlowLayout,
                                             UIScrollViewDelegate,
                                             SeafDentryDelegate,
                                             SeafPhotoContentDelegate>

@property (nonatomic, strong) UIPageViewController     *pageVC;
@property (nonatomic, assign) BOOL isDragging;
@end
