//
//  FailToPreview.m
//  seafile
//
//  Created by Wang Wei on 10/3/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "FailToPreview.h"
#import "Debug.h"


@interface FailToPreview ()
@property (strong, nonatomic) IBOutlet UILabel *errorLabel;
@end

@implementation FailToPreview


- (id)initWithCoder:(NSCoder *)decoder
{
    return [super initWithCoder:decoder];
}

- (void)configureViewWithPrevireItem:(id<SeafPreView>)item
{
    self.imageView.image = item.icon;
    self.nameLabel.text = item.previewItemTitle;
    self.errorLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@ does not support to preview file of this kind at the moment.", @"Seafile"), APP_NAME];
}

@end
