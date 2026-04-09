//
//  SeafPhotoPageContainer.h
//  seafileApp
//
//  Lightweight UIView wrapper that hosts a SeafPhotoContentViewController's
//  view inside SeafPhotoPagingView. Carries an explicit `pageIndex` to
//  replace the previous `view.tag`-based identity convention.
//
//  Created by henry on 2026/4/21.
//  Copyright © 2026 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>

@class SeafPhotoContentViewController;

NS_ASSUME_NONNULL_BEGIN

@interface SeafPhotoPageContainer : UIView

/// The page index this container represents. Defaults to NSNotFound for
/// freshly allocated containers; the data-source assigns the real index
/// before returning the container to the paging view.
@property (nonatomic, assign) NSUInteger pageIndex;

/// Weak back-reference to the content view controller hosted inside.
/// Strong ownership stays with `SeafPhotoGalleryViewController.contentVCCache`.
@property (nonatomic, weak, nullable) SeafPhotoContentViewController *contentVC;

@end

NS_ASSUME_NONNULL_END
