//
//  M13InfiniteTabBarController.m
//  M13InfiniteTabBar
/*
 Copyright (c) 2013 Brandon McQuilkin

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 One does not claim this software as ones own.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import "M13InfiniteTabBarController.h"
#import <QuartzCore/QuartzCore.h>

#import "M13InfiniteTabBarItem.h"


@interface M13InfiniteTabBarController ()
@property (nonatomic, assign) BOOL isCentralViewControllerOpen;
@end

@implementation M13InfiniteTabBarController
{
    M13InfiniteTabBarCentralPullViewController *_pullViewController;
    UIView *_maskView;
    UIView *_contentView;
    NSArray *_viewControllers;
    NSArray *_tabBarItems;
    BOOL _continueShowingAlert;
}

- (id)initWithViewControllers:(NSArray *)viewControllers pairedWithInfiniteTabBarItems:(NSArray *)items
{
    self = [super init];
    if (self) {
        _tabBarItems = items;
        _viewControllers = viewControllers;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    _continueShowingAlert = NO;

    //create content view to hold view controllers
    _contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height - 50.0)];
    _contentView.backgroundColor = [UIColor blackColor];
    _contentView.clipsToBounds = YES;

    //initalize the tab bar
    _infiniteTabBar = [[M13InfiniteTabBar alloc] initWithInfiniteTabBarItems:_tabBarItems];
    _infiniteTabBar.tabBarDelegate = self;

    //Create mask for tab bar
    _maskView = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.frame.size.height - 60.0, self.view.frame.size.width, 60.0)];
    //Add shadow gradient to mask layer
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = CGRectMake(0, 0, _infiniteTabBar.frame.size.width, 20);
    gradient.colors = [NSArray arrayWithObjects:(id)[[UIColor blackColor] CGColor], (id)[[UIColor clearColor] CGColor], nil];
    gradient.opacity = .4;

    //Combine views
    _maskView.backgroundColor = [UIColor underPageBackgroundColor];
    [self.view addSubview:_maskView];
    [_maskView.layer insertSublayer:gradient above:0];
    [_maskView addSubview:_infiniteTabBar];
    [self.view addSubview:_contentView];

    //Catch rotation changes for tabs
    //[[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    //[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleRotation:) name:UIDeviceOrientationDidChangeNotification object:nil];

    //Set Up View Controllers
    _selectedIndex = ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) ? 2 : 5;
    _selectedViewController = [_viewControllers objectAtIndex:_selectedIndex];
    _selectedViewController.view.frame = CGRectMake(0, 0, _contentView.frame.size.width, _contentView.frame.size.height);
    _selectedViewController.view.contentScaleFactor = [UIScreen mainScreen].scale;
    //[_contentView addSubview:_selectedViewController.view];

    for (UIViewController *controller in _viewControllers) {
        if (controller != _selectedViewController) {
            controller.view.contentScaleFactor = [UIScreen mainScreen].scale;
            controller.view.frame = CGRectMake(0, 0, _contentView.frame.size.width, _contentView.frame.size.height);
            controller.view.layer.opacity = 0.0;
        }
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [_selectedViewController viewWillAppear:animated];

    [_infiniteTabBar rotateItemsToOrientation:[UIDevice currentDevice].orientation];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [_selectedViewController viewWillDisappear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [_selectedViewController viewDidAppear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [_selectedViewController viewDidDisappear:animated];
}

- (void)dealloc
{
    if (_pullNotificatonBackgroundView) {
        [_pullNotificatonBackgroundView.layer removeAllAnimations];
    }
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

//Handle rotating all view controllers
- (void)handleRotation:(NSNotification *)notification
{
    UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;

    [UIView beginAnimations:@"HandleRotation" context:nil];
    [UIView setAnimationDuration:0.5];

    CGFloat angle = 0.0;
    if (orientation == UIDeviceOrientationLandscapeLeft) angle = M_PI_2;
    else if (orientation == UIDeviceOrientationLandscapeRight) angle = -M_PI_2;
    else if (orientation == UIDeviceOrientationPortraitUpsideDown) angle = M_PI;

    CGSize size = self.view.frame.size;
    CGFloat triangleDepth = 10.0;
    CGFloat statusBarHeight = [UIApplication sharedApplication].statusBarFrame.size.height;

    //Rotate Status Bar
    [[UIApplication sharedApplication] setStatusBarOrientation:orientation];
    //Rotate tab bar items
    [_infiniteTabBar rotateItemsToOrientation:orientation];
    //Recreate mask and adjust frames to make room for status bar.
    if (orientation == UIDeviceOrientationPortrait) {
        CGRect tempFrame = CGRectMake(0, 0, size.width, size.height - 50);
        _contentView.frame = tempFrame;
        _maskView.frame = CGRectMake(0, tempFrame.size.height - 10, _maskView.frame.size.width, _maskView.frame.size.height);

        //Create content mask
        CAShapeLayer *maskLayer = [[CAShapeLayer alloc] init];
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathMoveToPoint(path, NULL, 0, 0);
        CGPathAddLineToPoint(path, NULL, tempFrame.size.width, 0);
        CGPathAddLineToPoint(path, NULL, tempFrame.size.width, tempFrame.size.height);
        CGPathAddLineToPoint(path, NULL, (tempFrame.size.width / 2.0) + triangleDepth, tempFrame.size.height);
        CGPathAddLineToPoint(path, NULL, (tempFrame.size.width / 2.0), tempFrame.size.height - triangleDepth);
        CGPathAddLineToPoint(path, NULL, (tempFrame.size.width / 2.0) - triangleDepth, tempFrame.size.height);
        CGPathAddLineToPoint(path, NULL, 0, tempFrame.size.height);
        CGPathCloseSubpath(path);
        [maskLayer setPath:path];
        CGPathRelease(path);
        _contentView.layer.mask = maskLayer;
    } else if (orientation == UIDeviceOrientationPortraitUpsideDown) {
        CGRect tempFrame = CGRectMake(0, 0, size.width, size.height - 50);
        _contentView.frame = tempFrame;
        _maskView.frame = CGRectMake(0, tempFrame.size.height - 10 - statusBarHeight, _maskView.frame.size.width, _maskView.frame.size.height);

        tempFrame.size.height = tempFrame.size.height - statusBarHeight;

        //Create content mask
        CAShapeLayer *maskLayer = [[CAShapeLayer alloc] init];
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathMoveToPoint(path, NULL, 0, 0);
        CGPathAddLineToPoint(path, NULL, tempFrame.size.width, 0);
        CGPathAddLineToPoint(path, NULL, tempFrame.size.width, tempFrame.size.height);
        CGPathAddLineToPoint(path, NULL, (tempFrame.size.width / 2.0) + triangleDepth, tempFrame.size.height);
        CGPathAddLineToPoint(path, NULL, (tempFrame.size.width / 2.0), tempFrame.size.height - triangleDepth);
        CGPathAddLineToPoint(path, NULL, (tempFrame.size.width / 2.0) - triangleDepth, tempFrame.size.height);
        CGPathAddLineToPoint(path, NULL, 0, tempFrame.size.height);
        CGPathCloseSubpath(path);
        [maskLayer setPath:path];
        CGPathRelease(path);
        _contentView.layer.mask = maskLayer;
    } else if (orientation == UIDeviceOrientationLandscapeLeft) {
        CGRect tempFrame = CGRectMake(0, 0, size.width - statusBarHeight, size.height - 50);
        _contentView.frame = tempFrame;
        _maskView.frame = CGRectMake(-10, tempFrame.size.height - 10, _maskView.frame.size.width, _maskView.frame.size.height);

        //Create content mask
        CAShapeLayer *maskLayer = [[CAShapeLayer alloc] init];
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathMoveToPoint(path, NULL, 0, 0);
        CGPathAddLineToPoint(path, NULL, tempFrame.size.width, 0);
        CGPathAddLineToPoint(path, NULL, tempFrame.size.width, tempFrame.size.height);
        CGPathAddLineToPoint(path, NULL, (tempFrame.size.width / 2.0) + triangleDepth, tempFrame.size.height);
        CGPathAddLineToPoint(path, NULL, (tempFrame.size.width / 2.0), tempFrame.size.height - triangleDepth);
        CGPathAddLineToPoint(path, NULL, (tempFrame.size.width / 2.0) - triangleDepth, tempFrame.size.height);
        CGPathAddLineToPoint(path, NULL, 0, tempFrame.size.height);
        CGPathCloseSubpath(path);
        [maskLayer setPath:path];
        CGPathRelease(path);
        _contentView.layer.mask = maskLayer;
    } else if (orientation == UIDeviceOrientationLandscapeRight) {
        CGRect tempFrame = CGRectMake(0, 0, size.width - statusBarHeight, size.height - 50 + statusBarHeight);
        _contentView.frame = tempFrame;
        _maskView.frame = CGRectMake(statusBarHeight-10, tempFrame.size.height - 10 - statusBarHeight, _maskView.frame.size.width, _maskView.frame.size.height);

        //Create content mask
        CAShapeLayer *maskLayer = [[CAShapeLayer alloc] init];
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathMoveToPoint(path, NULL, 0, 0);
        CGPathAddLineToPoint(path, NULL, tempFrame.size.width, 0);
        CGPathAddLineToPoint(path, NULL, tempFrame.size.width, tempFrame.size.height);
        CGPathAddLineToPoint(path, NULL, (tempFrame.size.width / 2.0) + triangleDepth, tempFrame.size.height);
        CGPathAddLineToPoint(path, NULL, (tempFrame.size.width / 2.0), tempFrame.size.height - triangleDepth);
        CGPathAddLineToPoint(path, NULL, (tempFrame.size.width / 2.0) - triangleDepth, tempFrame.size.height);
        CGPathAddLineToPoint(path, NULL, 0, tempFrame.size.height);
        CGPathCloseSubpath(path);
        [maskLayer setPath:path];
        CGPathRelease(path);
        _contentView.layer.mask = maskLayer;
    }

    //Rotate View controllers bounds
    CGAffineTransform transform = CGAffineTransformMakeRotation(angle);
    for (UIViewController *viewController in _viewControllers) {
        if (orientation == UIDeviceOrientationPortrait) {
            CGRect tempFrame = CGRectMake(0, 0, size.width, size.height - 50);
            viewController.view.bounds = CGRectMake(0, 0, tempFrame.size.width, tempFrame.size.height);
        } else if (orientation == UIDeviceOrientationPortraitUpsideDown) {
            CGRect tempFrame = CGRectMake(0, -statusBarHeight, size.width, size.height - 50);
            viewController.view.bounds = CGRectMake(0, 0, tempFrame.size.width, tempFrame.size.height);
        } else if (orientation == UIDeviceOrientationLandscapeLeft) {
            CGRect tempFrame = CGRectMake(0, -statusBarHeight, size.width - statusBarHeight, size.height - 50 + statusBarHeight);
            viewController.view.bounds = CGRectMake(0, 0, tempFrame.size.height, tempFrame.size.width);
        } else if (orientation == UIDeviceOrientationLandscapeRight) {
            CGRect tempFrame = CGRectMake(0, -statusBarHeight, size.width - statusBarHeight, size.height - 50 + statusBarHeight);
            viewController.view.bounds = CGRectMake(0, 0, tempFrame.size.height, tempFrame.size.width);
        }
        viewController.view.transform = transform;
    }

    [UIView commitAnimations];
}

- (BOOL)shouldAutorotate
{
    return NO;
}

- (NSUInteger)supportedInterfaceOrientations
{
    [super supportedInterfaceOrientations];
    return UIInterfaceOrientationMaskPortrait;
}

//Tab bar delegate
- (BOOL)infiniteTabBar:(M13InfiniteTabBar *)tabBar shouldSelectItem:(M13InfiniteTabBarItem *)item
{
    BOOL should = YES;
    if ([_delegate respondsToSelector:@selector(infiniteTabBarController:shouldSelectViewContoller:)]) {
        should = [_delegate infiniteTabBarController:self shouldSelectViewContoller:[_viewControllers objectAtIndex:item.tag]];
    }
    return should;
}

- (void)infiniteTabBar:(M13InfiniteTabBar *)tabBar didSelectItem:(M13InfiniteTabBarItem *)item
{
    //Clean up animation
    if (_contentView.subviews.count > 1) {
        UIView *aView = [_contentView.subviews objectAtIndex:0];
        aView.layer.opacity = 0.0;
        [aView removeFromSuperview];
    }

    if ([_delegate respondsToSelector:@selector(infiniteTabBarController:didSelectViewController:)]) {
        [_delegate infiniteTabBarController:self didSelectViewController:[_viewControllers objectAtIndex:item.tag]];
    }
}

- (void)infiniteTabBar:(M13InfiniteTabBar *)tabBar animateInViewControllerForItem:(M13InfiniteTabBarItem *)item
{
    if ([[_viewControllers objectAtIndex:item.tag] isKindOfClass:[UINavigationController class]] && item.tag == _selectedIndex) {
        //Pop to root controller when tapped
        UINavigationController *controller = [_viewControllers objectAtIndex:item.tag];
        [controller popToRootViewControllerAnimated:YES];
    } else {
        UIViewController *newController = [_viewControllers objectAtIndex:item.tag];
        [_contentView addSubview:newController.view];
        newController.view.layer.opacity = 1.0;
        _selectedViewController = newController;
        _selectedIndex = [_viewControllers indexOfObject:newController];
    }
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex
{
    [_infiniteTabBar setSelectedItem:[_tabBarItems objectAtIndex:selectedIndex]];
}

- (void)setSelectedViewController:(UIViewController *)selectedViewController
{
    [_infiniteTabBar setSelectedItem:[_tabBarItems objectAtIndex:[_viewControllers indexOfObject:selectedViewController]]];
}

//Central View controller alerts
- (void)setCentralViewController:(UIViewController *)centralViewController
{
    //Add view
    _pullViewController = [[M13InfiniteTabBarCentralPullViewController alloc] initWithFrame:CGRectMake(0.0, self.view.frame.size.height, self.view.frame.size.width, self.view.frame.size.height)];
    _pullViewController.delegate = self;
    centralViewController.view.frame = CGRectMake(0.0, 30.0, self.view.frame.size.width, self.view.frame.size.height - 30.0);
    [_pullViewController addSubview:centralViewController.view];
    //set properties
    _pullViewController.closedCenter = _pullViewController.center;
    CGPoint openCenter = _pullViewController.center;
    openCenter.y = openCenter.y - self.view.frame.size.height;
    _pullViewController.openCenter = openCenter;
    //add handle view to view
    _pullViewController.handleView.frame = CGRectMake(0.0, 0.0, self.view.frame.size.width, 30.0);
    _pullViewController.handleView.backgroundColor = [UIColor clearColor];
    UIImage *handleImage = [UIImage imageNamed:@"Grabber.png"];
    UIImageView *handle = [[UIImageView alloc] initWithFrame:CGRectMake((_pullViewController.handleView.frame.size.width / 2.0) - (handleImage.size.width / 2.0), _pullViewController.handleView.frame.size.height - handleImage.size.height, handleImage.size.width, handleImage.size.height)];
    handle.layer.opacity = 0.3;
    [handle setImage:handleImage];
    [_pullViewController.handleView addSubview:handle];
    //Add gesture to tab bar
    M13PanGestureRecognizer *dragRecoginizer = [[M13PanGestureRecognizer alloc] initWithTarget:_pullViewController action:@selector(handleDrag:)];
    dragRecoginizer.panDirection = M13PanGestureRecognizerDirectionVertical;
    dragRecoginizer.minimumNumberOfTouches = 1;
    dragRecoginizer.maximumNumberOfTouches = 1;
    dragRecoginizer.delegate = _infiniteTabBar;
    dragRecoginizer.cancelsTouchesInView = NO;
    dragRecoginizer.delaysTouchesBegan = NO;
    [_infiniteTabBar addGestureRecognizer:dragRecoginizer];
    //Appearance
    _pullViewController.backgroundColor = centralViewController.view.backgroundColor;
    centralViewController.view.backgroundColor = [UIColor clearColor];

    //Add pull view to tab bar
    [self.view addSubview:_pullViewController];

    //Other
    _continueShowingAlert = YES;
}

- (void)pullableView:(M13InfiniteTabBarCentralPullViewController *)pullableView didChangeState:(BOOL)isOpen
{
    if (!isOpen) {
        [self endAlertAnimation];
    }
}

- (void)showAlertForCentralViewControllerIsEmergency:(BOOL)emergency
{
    if (_pullViewController != nil) {
        _continueShowingAlert = YES;
        if (_pullNotificatonBackgroundView == nil) {
            _pullNotificatonBackgroundView = [[M13InfiniteTabBarCentralPullNotificationBackgroundView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width, 0)];
            _pullNotificatonBackgroundView.layer.opacity = 0.0;
            [_maskView insertSubview:_pullNotificatonBackgroundView belowSubview:_infiniteTabBar];
        }
        _pullNotificatonBackgroundView.frame = CGRectMake(0.0, 0.0, _pullNotificatonBackgroundView.frame.size.width, _pullNotificatonBackgroundView.frame.size.height);
        [_pullNotificatonBackgroundView setIsEmergency:emergency];
        [UIView beginAnimations:@"Chevron Animation" context:nil];
        [UIView setAnimationDelegate:self];
        [UIView setAnimationDidStopSelector:@selector(repeatAlertAnimation)];
        [UIView setAnimationDuration:2.0];
        [UIView setAnimationCurve:UIViewAnimationCurveLinear];
        _pullNotificatonBackgroundView.layer.opacity = 1.0;
        _pullNotificatonBackgroundView.frame = CGRectMake(0, -_pullNotificatonBackgroundView.notificationPatternRepeatDistance, _pullNotificatonBackgroundView.frame.size.width, _pullNotificatonBackgroundView.frame.size.height);
        [UIView commitAnimations];
    }
}

- (void)endAlertAnimation
{
    _continueShowingAlert = NO;
}

- (void)repeatAlertAnimation
{
    if (_continueShowingAlert) { //repeat
        _pullNotificatonBackgroundView.frame = CGRectMake(0, 0, _pullNotificatonBackgroundView.frame.size.width, _pullNotificatonBackgroundView.frame.size.height);
        [UIView beginAnimations:@"CheveronAnimation" context:nil];
        [UIView setAnimationDelegate:self];
        [UIView setAnimationDidStopSelector:@selector(repeatAlertAnimation)];
        [UIView setAnimationDuration:2.0];
        [UIView setAnimationRepeatCount:5];
        [UIView setAnimationCurve:UIViewAnimationCurveLinear];
        _pullNotificatonBackgroundView.frame = CGRectMake(0, -_pullNotificatonBackgroundView.notificationPatternRepeatDistance, _pullNotificatonBackgroundView.frame.size.width, _pullNotificatonBackgroundView.frame.size.height);
        [UIView commitAnimations];
    } else { //end
        _pullNotificatonBackgroundView.frame = CGRectMake(0, 0, _pullNotificatonBackgroundView.frame.size.width, _pullNotificatonBackgroundView.frame.size.height);
        [UIView beginAnimations:@"CheveronAnimation" context:nil];
        [UIView setAnimationDelegate:self];
        [UIView setAnimationDidStopSelector:@selector(repeatAnimation)];
        [UIView setAnimationDuration:2.0];
        [UIView setAnimationCurve:UIViewAnimationCurveLinear];
        _pullNotificatonBackgroundView.layer.opacity = 0.0;
        _pullNotificatonBackgroundView.frame = CGRectMake(0, -_pullNotificatonBackgroundView.notificationPatternRepeatDistance, _pullNotificatonBackgroundView.frame.size.width, _pullNotificatonBackgroundView.frame.size.height);
        [UIView commitAnimations];
    }
}

- (void)setCentralViewControllerOpened:(BOOL)opened animated:(BOOL)animated
{
    [_pullViewController setOpened:opened animated:animated];
}

//Appearance
- (void)setTabBarBackgroundColor:(UIColor *)tabBarBackgroundColor
{
    _maskView.backgroundColor = tabBarBackgroundColor;
    _tabBarBackgroundColor = tabBarBackgroundColor;
}

@end
