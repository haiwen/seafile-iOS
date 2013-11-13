//
//  SeafEmptyViewController.m
//  seafilePro
//
//  Created by Wang Wei on 5/29/13.
//  Copyright (c) 2013 Seafile Ltd. All rights reserved.
//

#import "SeafEmptyViewController.h"
#import "UIViewController+Extend.h"
#import "Debug.h"

@interface SeafEmptyViewController ()

@end

@implementation SeafEmptyViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(BOOL)shouldAutorotate
{
    return YES;
}

-(NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscapeRight| UIInterfaceOrientationMaskLandscapeLeft | UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown;
}

@end
