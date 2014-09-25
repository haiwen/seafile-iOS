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
@property (strong) id<SeafPreView> item;
@property (strong) UIDocumentInteractionController *docController;
@property (strong, nonatomic) IBOutlet UILabel *errorLabel;
@property (strong, nonatomic) IBOutlet ColorfulButton *openElseBtn;
@end

@implementation FailToPreview


- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super initWithCoder:decoder];
    _errorLabel.text = NSLocalizedString(@"Seafile does not support to preview file of this kind at the moment.", @"Seafile");
    _openElseBtn.titleLabel.text = NSLocalizedString(@"Open in other applications", @"Seafile");
    for (UIView *v in self.subviews) {
        v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin| UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin;
    }
    self.autoresizesSubviews = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    return self;
}

- (IBAction)openElsewhere:(id)sender
{
    NSURL *url = [_item exportURL];
    if (!url) return;
    _docController = [UIDocumentInteractionController interactionControllerWithURL:url];
    BOOL ret = [_docController presentOpenInMenuFromRect:[((UIButton *)sender) frame] inView:self animated:YES];
    if (ret == NO) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"There is no app which can open this type of file on this machine", @"Seafile")
                                                        message:nil
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
    }
}

- (void)configureViewWithPrevireItem:(id<SeafPreView>)item
{
    _item = item;
    self.imageView.image = _item.icon;
    self.nameLabel.text = _item.previewItemTitle;
}

@end
