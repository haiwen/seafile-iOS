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
@property (strong) id<QLPreviewItem, PreViewDelegate> item;
@property (strong) UIDocumentInteractionController *docController;
@end

@implementation FailToPreview
@synthesize imageView;
@synthesize nameLabel;
@synthesize item = _item;
@synthesize docController;


- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];
    for (UIView *v in self.subviews) {
        v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin| UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin;
    }
    self.autoresizesSubviews = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    return self;
}

- (IBAction)openElsewhere:(id)sender
{
    NSURL *url = [_item checkoutURL];
    if (!url)
        return;
    docController = [UIDocumentInteractionController interactionControllerWithURL:url];
    BOOL ret = [docController presentOpenInMenuFromRect:[((UIButton *)sender) frame] inView:self animated:YES];
    if (ret == NO) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"There is no app which can open this type of file on this machine"
                                                        message:nil
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
    }
}

- (void)configureViewWithPrevireItem:(id<QLPreviewItem, PreViewDelegate>)item
{
    _item = item;
    self.imageView.image = _item.image;
    self.nameLabel.text = _item.previewItemTitle;
}

@end
