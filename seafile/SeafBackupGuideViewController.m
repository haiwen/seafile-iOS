//
//  SeafBackupGuideViewController.m
//  seafile
//
//  Created by Henry on 2025/6/9.
//  Copyright © 2024 Seafile Ltd. All rights reserved.
//

#import "SeafBackupGuideViewController.h"
#import "SeafBackupDirViewController.h"
#import "SeafRepos.h"
#import "SeafConnection.h"
#import "Debug.h"
#import "SeafAppDelegate.h"
#import "Utils.h"
#import "SVProgressHUD.h"

typedef NS_ENUM(NSInteger, SeafBackupButtonType) {
    SeafBackupButtonTypePhotos = 0,
    SeafBackupButtonTypeVideos = 1,
    SeafBackupButtonTypeHeic = 2,
    SeafBackupButtonTypeWifiOnly = 10,
    SeafBackupButtonTypeCellular = 11
};

@interface SeafBackupGuideViewController () <SeafDirDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate>

@property (strong, nonatomic) UIScrollView *scrollView;
@property (strong, nonatomic) UIPageControl *pageControl;
@property (strong, nonatomic) UIView *nextActionView;
@property (strong, nonatomic) UILabel *nextActionLabel;
@property (strong, nonatomic) UIImageView *nextActionIcon;
@property (strong, nonatomic) SeafBackupDirViewController *dirViewController;
@property (strong, nonatomic) SeafRepo *selectedRepo;
@property (strong, nonatomic) UILabel *titleLabel;
@property (strong, nonatomic) UILabel *subtitleLabel;

@property (strong, nonatomic) UIView *page2View;
@property (strong, nonatomic) UIButton *backupPhotosButton;
@property (strong, nonatomic) UIButton *backupVideosButton;
@property (strong, nonatomic) UIButton *backupHeicButton;

@property (strong, nonatomic) UIView *page3View;
@property (strong, nonatomic) UIButton *wifiOnlyButton;
@property (strong, nonatomic) UIButton *cellularButton;
@property (strong, nonatomic) NSLayoutConstraint *nextButtonWidthConstraint;
@property (strong, nonatomic) NSLayoutConstraint *nextButtonHeightConstraint;
@property (strong, nonatomic) UIView *topSeparatorLine;
@property (strong, nonatomic) UIView *bottomSeparatorLine;
@property (strong, nonatomic) UIView *heicOptionView;
@property (strong, nonatomic) UIButton *startButton;

@end

@implementation SeafBackupGuideViewController

- (instancetype)initWithConnection:(SeafConnection *)connection {
    if (self = [super init]) {
        _connection = connection;
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    if ([self.navigationController respondsToSelector:@selector(interactivePopGestureRecognizer)]) {
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];

    [self setupTitleLabel];
    [self setupScrollView];
    [self setupNextActionView];
    [self setupPageControl];
    [self setupDirViewController];
    [self setupBackupOptionsView];
    [self setupBackupMethodView];
    [self setupStartButton];
    [self setupSwipeGesture];
    [self updateHeicOptionState];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
}

- (void)setupScrollView {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.delegate = self;
    self.scrollView.pagingEnabled = YES;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    [self.view addSubview:self.scrollView];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
}

- (void)setupTitleLabel {
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [self.view addSubview:self.titleLabel];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:28],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28]
    ]];

    self.titleLabel.text = NSLocalizedString(@"Select Backup Location", @"Seafile");
    self.titleLabel.textColor = [UIColor blackColor];
}

- (void)setupPageControl {
    self.pageControl = [[UIPageControl alloc] init];
    self.pageControl.numberOfPages = 3;
    self.pageControl.currentPage = 0;
    self.pageControl.pageIndicatorTintColor = [UIColor lightGrayColor];
    self.pageControl.currentPageIndicatorTintColor = [UIColor orangeColor];
    self.pageControl.userInteractionEnabled = NO;
    [self.view addSubview:self.pageControl];

    self.pageControl.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.pageControl.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-40],
        [self.pageControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.pageControl.centerYAnchor constraintEqualToAnchor:self.nextActionView.centerYAnchor]
    ]];
}

- (void)setupNextActionView {
    self.nextActionView = [[UIView alloc] init];
    [self.view addSubview:self.nextActionView];
    self.nextActionView.translatesAutoresizingMaskIntoConstraints = NO;

    self.nextActionLabel = [[UILabel alloc] init];
    self.nextActionLabel.text = NSLocalizedString(@"Next", @"Seafile");
    self.nextActionLabel.textColor = [UIColor orangeColor];
    self.nextActionLabel.font = [UIFont systemFontOfSize:17];
    [self.nextActionView addSubview:self.nextActionLabel];
    self.nextActionLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.nextActionIcon = [[UIImageView alloc] init];
    UIImage *nextImage = [UIImage imageNamed:@"backupGuide_next"];
    if (nextImage) {
        CGFloat newHeight = 8.0;
        CGFloat scale = newHeight / nextImage.size.height;
        CGFloat newWidth = nextImage.size.width * scale;
        CGSize newSize = CGSizeMake(newWidth, newHeight);
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:newSize];
        UIImage *resizedImage = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
            [nextImage drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
        }];
        self.nextActionIcon.image = resizedImage;
    }
    [self.nextActionView addSubview:self.nextActionIcon];
    self.nextActionIcon.translatesAutoresizingMaskIntoConstraints = NO;

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(nextPressed:)];
    [self.nextActionView addGestureRecognizer:tapGesture];

//    self.nextActionView.userInteractionEnabled = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.nextActionView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-40],
        [self.nextActionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22],

        [self.nextActionLabel.leadingAnchor constraintEqualToAnchor:self.nextActionView.leadingAnchor],
        [self.nextActionLabel.centerYAnchor constraintEqualToAnchor:self.nextActionView.centerYAnchor],
        [self.nextActionLabel.topAnchor constraintEqualToAnchor:self.nextActionView.topAnchor],
        [self.nextActionLabel.bottomAnchor constraintEqualToAnchor:self.nextActionView.bottomAnchor],

        [self.nextActionIcon.leadingAnchor constraintEqualToAnchor:self.nextActionLabel.trailingAnchor constant:5],
        [self.nextActionIcon.trailingAnchor constraintEqualToAnchor:self.nextActionView.trailingAnchor],
        [self.nextActionIcon.centerYAnchor constraintEqualToAnchor:self.nextActionView.centerYAnchor constant:2],
    ]];
}

- (void)setupDirViewController {
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.text = NSLocalizedString(@"Select a directory", @"Seafile");
    self.subtitleLabel.font = [UIFont systemFontOfSize:14];
    self.subtitleLabel.textColor = [UIColor darkGrayColor];
    [self.view addSubview:self.subtitleLabel];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:33],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28]
    ]];

    self.dirViewController = [[SeafBackupDirViewController alloc] initWithSeafDir:self.connection.rootFolder delegate:self chooseRepo:true];
    self.dirViewController.operationState = OPERATION_STATE_OTHER;
    
    [self addChildViewController:self.dirViewController];
    [self.scrollView addSubview:self.dirViewController.view];
    [self.dirViewController didMoveToParentViewController:self];

    self.dirViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.dirViewController.view.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.dirViewController.view.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.dirViewController.view.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
        [self.dirViewController.view.heightAnchor constraintEqualToAnchor:self.scrollView.heightAnchor],

        [self.scrollView.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:6],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.pageControl.topAnchor constant:-45],
    ]];

    self.topSeparatorLine = [[UIView alloc] init];
    self.topSeparatorLine.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    self.topSeparatorLine.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.topSeparatorLine];

    self.bottomSeparatorLine = [[UIView alloc] init];
    self.bottomSeparatorLine.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    self.bottomSeparatorLine.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.bottomSeparatorLine];

    [NSLayoutConstraint activateConstraints:@[
        [self.topSeparatorLine.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.topSeparatorLine.leadingAnchor constraintEqualToAnchor:self.subtitleLabel.leadingAnchor constant:-5],
        [self.topSeparatorLine.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.topSeparatorLine.heightAnchor constraintEqualToConstant:0.5],

        [self.bottomSeparatorLine.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.bottomSeparatorLine.leadingAnchor constraintEqualToAnchor:self.subtitleLabel.leadingAnchor constant:-5],
        [self.bottomSeparatorLine.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.bottomSeparatorLine.heightAnchor constraintEqualToConstant:0.5]
    ]];
}

- (void)setupBackupOptionsView {
    self.page2View = [[UIView alloc] init];
    [self.scrollView addSubview:self.page2View];
    self.page2View.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.page2View.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.page2View.leadingAnchor constraintEqualToAnchor:self.dirViewController.view.trailingAnchor],
        [self.page2View.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
        [self.page2View.heightAnchor constraintEqualToAnchor:self.scrollView.heightAnchor]
    ]];

    UIView *photosOption = [self createOptionViewWithTitle:NSLocalizedString(@"Back up photos", @"Seafile") type:SeafBackupButtonTypePhotos selected:YES];
    UIView *videosOption = [self createOptionViewWithTitle:NSLocalizedString(@"Back up photos and videos", @"Seafile") type:SeafBackupButtonTypeVideos selected:NO];
    self.heicOptionView = [self createOptionViewWithTitle:NSLocalizedString(@"Upload Live Photo as Motion Photo", @"Seafile") type:SeafBackupButtonTypeHeic selected:NO];

    [self.backupPhotosButton removeTarget:self action:@selector(optionTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.backupVideosButton removeTarget:self action:@selector(optionTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.backupPhotosButton addTarget:self action:@selector(backupOptionTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.backupVideosButton addTarget:self action:@selector(backupOptionTapped:) forControlEvents:UIControlEventTouchUpInside];

    [self.page2View addSubview:photosOption];
    [self.page2View addSubview:videosOption];
    [self.page2View addSubview:self.heicOptionView];

    photosOption.translatesAutoresizingMaskIntoConstraints = NO;
    videosOption.translatesAutoresizingMaskIntoConstraints = NO;
    self.heicOptionView.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [photosOption.topAnchor constraintEqualToAnchor:self.page2View.topAnchor constant:20],
        [photosOption.leadingAnchor constraintEqualToAnchor:self.page2View.leadingAnchor constant:26],
        [photosOption.trailingAnchor constraintEqualToAnchor:self.page2View.trailingAnchor constant:-20],

        [videosOption.topAnchor constraintEqualToAnchor:photosOption.bottomAnchor constant:15],
        [videosOption.leadingAnchor constraintEqualToAnchor:photosOption.leadingAnchor],
        [videosOption.trailingAnchor constraintEqualToAnchor:photosOption.trailingAnchor],

        [self.heicOptionView.topAnchor constraintEqualToAnchor:videosOption.bottomAnchor constant:30],
        [self.heicOptionView.leadingAnchor constraintEqualToAnchor:photosOption.leadingAnchor],
        [self.heicOptionView.trailingAnchor constraintEqualToAnchor:photosOption.trailingAnchor],
    ]];

    CGFloat imageSize = [self isSmallScreen] ? 180 : 200;
    CGFloat bottomConstant = [self isSmallScreen] ? -10 : -25;
    CGFloat centerXConstant = [self isSmallScreen] ? 40 : 60;
    UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"backupGuide_page2"]];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.page2View addSubview:imageView];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [imageView.centerXAnchor constraintEqualToAnchor:self.page2View.centerXAnchor constant:centerXConstant],
        [imageView.bottomAnchor constraintEqualToAnchor:self.page2View.bottomAnchor constant:bottomConstant],
        [imageView.widthAnchor constraintEqualToConstant:imageSize],
        [imageView.heightAnchor constraintEqualToConstant:imageSize]
    ]];
}

- (void)setupBackupMethodView {
    self.page3View = [[UIView alloc] init];
    [self.scrollView addSubview:self.page3View];
    self.page3View.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.page3View.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.page3View.leadingAnchor constraintEqualToAnchor:self.page2View.trailingAnchor],
        [self.page3View.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.page3View.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
        [self.page3View.heightAnchor constraintEqualToAnchor:self.scrollView.heightAnchor]
    ]];

    UIView *wifiOnlyOption = [self createOptionViewWithTitle:NSLocalizedString(@"Auto-sync only on Wi-Fi", @"Seafile") type:SeafBackupButtonTypeWifiOnly selected:NO];
    UIView *cellularOption = [self createOptionViewWithTitle:NSLocalizedString(@"Wi-Fi or cellular data", @"Seafile") type:SeafBackupButtonTypeCellular selected:YES];

    [self.wifiOnlyButton removeTarget:self action:@selector(optionTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.cellularButton removeTarget:self action:@selector(optionTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.wifiOnlyButton addTarget:self action:@selector(wifiOptionTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.cellularButton addTarget:self action:@selector(wifiOptionTapped:) forControlEvents:UIControlEventTouchUpInside];

    [self.page3View addSubview:wifiOnlyOption];
    [self.page3View addSubview:cellularOption];

    wifiOnlyOption.translatesAutoresizingMaskIntoConstraints = NO;
    cellularOption.translatesAutoresizingMaskIntoConstraints = NO;

    CGFloat optionSpacing = [self isSmallScreen] ? 10 : 15;
    [NSLayoutConstraint activateConstraints:@[
        [wifiOnlyOption.topAnchor constraintEqualToAnchor:self.page3View.topAnchor constant:20],
        [wifiOnlyOption.leadingAnchor constraintEqualToAnchor:self.page3View.leadingAnchor constant:26],
        [wifiOnlyOption.trailingAnchor constraintEqualToAnchor:self.page3View.trailingAnchor constant:-20],

        [cellularOption.topAnchor constraintEqualToAnchor:wifiOnlyOption.bottomAnchor constant:optionSpacing],
        [cellularOption.leadingAnchor constraintEqualToAnchor:wifiOnlyOption.leadingAnchor],
        [cellularOption.trailingAnchor constraintEqualToAnchor:wifiOnlyOption.trailingAnchor],
    ]];

    CGFloat imageSize = [self isSmallScreen] ? 150 : 200;
    CGFloat bottomConstant = [self isSmallScreen] ? -10 : -25;
    CGFloat centerXConstant = [self isSmallScreen] ? 30 : 50;
    UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"backupGuide_page3"]];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.page3View addSubview:imageView];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [imageView.centerXAnchor constraintEqualToAnchor:self.page3View.centerXAnchor constant:centerXConstant],
        [imageView.bottomAnchor constraintEqualToAnchor:self.page3View.bottomAnchor constant:bottomConstant],
        [imageView.widthAnchor constraintEqualToConstant:imageSize],
        [imageView.heightAnchor constraintEqualToConstant:imageSize]
    ]];
}

- (void)setupStartButton {
    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startButton setTitle:NSLocalizedString(@"Start", @"Seafile") forState:UIControlStateNormal];
    [self.startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startButton.backgroundColor = [UIColor orangeColor];
    self.startButton.layer.cornerRadius = 6.0;
    self.startButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.startButton addTarget:self action:@selector(nextPressed:) forControlEvents:UIControlEventTouchUpInside];
    self.startButton.hidden = YES;
    
    [self.view addSubview:self.startButton];
    self.startButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.startButton.centerYAnchor constraintEqualToAnchor:self.nextActionView.centerYAnchor],
        [self.startButton.trailingAnchor constraintEqualToAnchor:self.nextActionView.trailingAnchor],
        [self.startButton.widthAnchor constraintEqualToConstant:100],
        [self.startButton.heightAnchor constraintEqualToConstant:36]
    ]];
}

- (BOOL)isSmallScreen {
    return [UIScreen mainScreen].bounds.size.width <= 375.0;
}

- (UIView *)createOptionViewWithTitle:(NSString *)title type:(SeafBackupButtonType)type selected:(BOOL)selected {
    UIView *view = [[UIView alloc] init];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = type;
    UIImage *unselectedImage;
    UIImage *selectedImage;

    if (type == SeafBackupButtonTypeHeic) {
        unselectedImage = [[UIImage systemImageNamed:@"circle"] imageWithTintColor:[UIColor grayColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        selectedImage = [[UIImage systemImageNamed:@"checkmark.circle.fill"] imageWithTintColor:[UIColor orangeColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    } else {
        unselectedImage = [[UIImage systemImageNamed:@"circle"] imageWithTintColor:[UIColor grayColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        selectedImage = [[UIImage systemImageNamed:@"circle.inset.filled"] imageWithTintColor:[UIColor orangeColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    [button setImage:unselectedImage forState:UIControlStateNormal];
    [button setImage:selectedImage forState:UIControlStateSelected];
    button.selected = selected;
    [button addTarget:self action:@selector(optionTapped:) forControlEvents:UIControlEventTouchUpInside];

    switch (type) {
        case SeafBackupButtonTypePhotos:
            self.backupPhotosButton = button;
            break;
        case SeafBackupButtonTypeVideos:
            self.backupVideosButton = button;
            break;
        case SeafBackupButtonTypeHeic:
            self.backupHeicButton = button;
            break;
        case SeafBackupButtonTypeWifiOnly:
            self.wifiOnlyButton = button;
            break;
        case SeafBackupButtonTypeCellular:
            self.cellularButton = button;
            break;
    }

    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    if ([self isSmallScreen]) {
        label.font = [UIFont systemFontOfSize:15];
    }

    [view addSubview:button];
    [view addSubview:label];

    button.translatesAutoresizingMaskIntoConstraints = NO;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    CGFloat viewHeight = [self isSmallScreen] ? 25 : 30;
    CGFloat labelLeading = [self isSmallScreen] ? 8 : 10;
    [NSLayoutConstraint activateConstraints:@[
        [button.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [button.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
        [button.widthAnchor constraintEqualToConstant:24],
        [button.heightAnchor constraintEqualToConstant:24],

        [label.leadingAnchor constraintEqualToAnchor:button.trailingAnchor constant:labelLeading],
        [label.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],

        [view.heightAnchor constraintEqualToConstant:viewHeight]
    ]];

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(optionViewTapped:)];
    [view addGestureRecognizer:tapGesture];

    return view;
}

- (void)optionTapped:(UIButton *)sender {
    sender.selected = !sender.selected;
}

- (void)backupOptionTapped:(UIButton *)sender {
    self.backupPhotosButton.selected = (sender == self.backupPhotosButton);
    self.backupVideosButton.selected = (sender == self.backupVideosButton);
    [self updateHeicOptionState];
}

- (void)updateHeicOptionState {
    self.heicOptionView.userInteractionEnabled = YES;
    self.heicOptionView.alpha = 1.0;
}

- (void)wifiOptionTapped:(UIButton *)sender {
    self.wifiOnlyButton.selected = (sender == self.wifiOnlyButton);
    self.cellularButton.selected = (sender == self.cellularButton);
}

- (void)optionViewTapped:(UITapGestureRecognizer *)gesture {
    UIButton *button = nil;
    for (UIView *subview in gesture.view.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            button = (UIButton *)subview;
            break;
        }
    }
    if (button) {
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)nextPressed:(id)sender {
    NSInteger currentPage = self.pageControl.currentPage;
    if (currentPage == 0 && !self.selectedRepo) {
        [SVProgressHUD showInfoWithStatus:NSLocalizedString(@"Please select a directory", @"Seafile")];
        return;
    }
    if (currentPage < self.pageControl.numberOfPages - 1) {
        CGFloat newX = self.scrollView.bounds.size.width * (currentPage + 1);
        [self.scrollView setContentOffset:CGPointMake(newX, 0) animated:YES];
    } else {
        Debug("BackupGuide: completing setup, backupHeicButton.selected=%d, current uploadLivePhotoEnabled=%d, hasRespondedToLivePhotoReuploadPrompt=%d",
              self.backupHeicButton.selected, self.connection.isUploadLivePhotoEnabled, self.connection.hasRespondedToLivePhotoReuploadPrompt);
        
        self.connection.videoSync = self.backupVideosButton.selected;
        // ============ Live Photo / Motion Photo upload setting ============
        // This button now only controls Live Photo upload behavior
        [self.connection setUploadLivePhotoEnabled:self.backupHeicButton.selected];
        
        Debug("BackupGuide: after setUploadLivePhotoEnabled, uploadLivePhotoEnabled=%d", self.connection.isUploadLivePhotoEnabled);

        self.connection.wifiOnly = self.wifiOnlyButton.selected;
        
        NSString *key = [NSString stringWithFormat:@"hasCompletedBackupGuide_%@_%@", self.connection.address, self.connection.username];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:key];

        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate checkBackgroundUploadStatus];

        if (self.selectedRepo) {
            [self.delegate backupGuide:self didFinishWithRepo:self.selectedRepo];
        }
    }
}

- (void)setupSwipeGesture {
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeRight:)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    swipeRight.delegate = self;
    [self.view addGestureRecognizer:swipeRight];
    [self.scrollView.panGestureRecognizer requireGestureRecognizerToFail:swipeRight];
}

- (void)handleSwipeRight:(UISwipeGestureRecognizer *)gesture {
    [self.delegate backupGuideDidCancel:self];
}

#pragma mark - SeafDirDelegate
- (void)chooseDir:(UIViewController *)c dir:(SeafDir *)dir {
    if (dir && ![dir isKindOfClass:[SeafRepo class]]) {
        return;
    }
    SeafRepo *repo = (SeafRepo *)dir;
    if (repo && repo.encrypted) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Encrypted libraries cannot be used for backup.", @"Seafile")];
        return;
    }
    self.selectedRepo = repo;
    self.dirViewController.selectedRepo = repo;
    [self.dirViewController.tableView reloadData];
}

#pragma mark - UIScrollViewDelegate
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    CGFloat targetPage = targetContentOffset->x / self.view.frame.size.width;
    if (targetPage > 0.5 && !self.selectedRepo) {
        targetContentOffset->x = 0;
        [SVProgressHUD showInfoWithStatus:NSLocalizedString(@"Please select a directory", @"Seafile")];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat pageIndex = round(scrollView.contentOffset.x / self.view.frame.size.width);
    self.pageControl.currentPage = (int)pageIndex;

    if (pageIndex == 0) {
        self.subtitleLabel.hidden = NO;
        self.titleLabel.text = NSLocalizedString(@"Select Backup Location", @"Seafile");
        self.subtitleLabel.text = NSLocalizedString(@"Select a directory", @"Seafile");
        self.topSeparatorLine.hidden = NO;
        self.bottomSeparatorLine.hidden = NO;
    } else if (pageIndex == 1) {
        self.subtitleLabel.hidden = NO;
        self.titleLabel.text = NSLocalizedString(@"Select Backup Content", @"Seafile");
        self.subtitleLabel.text = NSLocalizedString(@"Please select content to upload", @"Seafile");
        self.nextActionView.userInteractionEnabled = YES;
        self.topSeparatorLine.hidden = YES;
        self.bottomSeparatorLine.hidden = YES;
    } else if (pageIndex == 2) {
        self.subtitleLabel.hidden = NO;
        self.titleLabel.text = NSLocalizedString(@"Select Backup Method", @"Seafile");
        self.subtitleLabel.text = NSLocalizedString(@"Please select upload method", @"Seafile");
        self.nextActionView.userInteractionEnabled = YES;
        self.topSeparatorLine.hidden = YES;
        self.bottomSeparatorLine.hidden = YES;
    }

    if (self.pageControl.currentPage == self.pageControl.numberOfPages - 1) {
        self.nextActionView.hidden = YES;
        self.startButton.hidden = NO;
    } else {
        self.nextActionView.hidden = NO;
        self.startButton.hidden = YES;
    }
}

#pragma mark - UIGestureRecognizerDelegate
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.navigationController.interactivePopGestureRecognizer) {
        // Only allow pop gesture on the first page
        return self.pageControl.currentPage == 0;
    }
    if ([gestureRecognizer isKindOfClass:[UISwipeGestureRecognizer class]]) {
        return self.pageControl.currentPage == 0;
    }
    return YES;
}

@end 
