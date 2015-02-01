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
@property (strong) UIDocumentInteractionController *docController;
@property (strong, nonatomic) IBOutlet UILabel *errorLabel;
@end

@implementation FailToPreview


- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];
    _errorLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@ does not support to preview file of this kind at the moment.", @"Seafile"), APP_NAME];
    _openElseBtn.titleLabel.text = NSLocalizedString(@"Open in other applications", @"Seafile");
    for (UIView *v in self.subviews) {
        v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin| UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin;
    }
    self.autoresizesSubviews = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    return self;
}

- (void)configureViewWithPrevireItem:(id<SeafPreView>)item
{
    self.imageView.image = item.icon;
    self.nameLabel.text = item.previewItemTitle;
}

@end
