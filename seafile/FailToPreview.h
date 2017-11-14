//
//  FailToPreview.h
//  seafile
//
//  Created by Wang Wei on 10/3/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>
#import "ColorfulButton.h"
#import "SeafPreView.h"

@interface FailToPreview : UIView
@property (strong, nonatomic) IBOutlet UIImageView *imageView;
@property (strong, nonatomic) IBOutlet UILabel *nameLabel;

- (void)configureViewWithPrevireItem:(id<SeafPreView>)item;

@end
