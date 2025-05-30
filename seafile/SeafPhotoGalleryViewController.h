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
