// Copyright 2013 Care Zone Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "CZPhotoPreviewViewController.h"

@interface CZPhotoPreviewViewController ()

@property(nonatomic,copy) dispatch_block_t cancelBlock;
@property(nonatomic,copy) dispatch_block_t chooseBlock;
@property(nonatomic,strong) UIImage *image;
@property(nonatomic,weak) IBOutlet UIImageView *imageView;
@property(nonatomic,weak) IBOutlet UILabel *previewLabel;
@property(nonatomic,weak) IBOutlet UIToolbar *toolbar;

@end

@implementation CZPhotoPreviewViewController

#pragma mark - Lifecycle

- (id)initWithImage:(UIImage *)anImage chooseBlock:(dispatch_block_t)chooseBlock cancelBlock:(dispatch_block_t)cancelBlock
{
    NSParameterAssert(chooseBlock);
    NSParameterAssert(cancelBlock);

    self = [super initWithNibName:nil bundle:nil];

    if (self) {
        self.cancelBlock = cancelBlock;
        self.chooseBlock = chooseBlock;
        self.image = anImage;
        self.title = NSLocalizedString(@"Choose Photo", nil);
    }

    return self;
}

#pragma mark - Methods

- (IBAction)didCancel:(id)sender
{
    self.cancelBlock();
}

- (IBAction)didChoose:(id)sender
{
    self.chooseBlock();
}

#pragma mark - UIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.imageView.image = self.image;

    // No toolbar on iPad, use the nav bar. Mimic how Mail.app’s picker works

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        self.toolbar.hidden = YES;
        self.previewLabel.hidden = YES;

        // Intentionally not using the bar buttons from the xib as that causes
        // a weird re-layout.

        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(didCancel:)];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Upload", nil) style:UIBarButtonItemStyleBordered target:self action:@selector(didChoose:)];
    }
    else {
        self.toolbar.tintColor = [UIColor blackColor];
        [self.navigationController setNavigationBarHidden:YES animated:YES];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    CGSize size = CGSizeMake(320, 480);

    self.contentSizeForViewInPopover = size;

    [super viewWillAppear:animated];
}

@end
