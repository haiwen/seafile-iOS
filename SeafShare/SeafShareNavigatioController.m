//
//  SeafShareNavigatioController.m
//  SeafShare
//
//  Created by three on 2018/7/29.
//  Copyright © 2018年 Seafile. All rights reserved.
//

#import "SeafShareNavigatioController.h"

@interface SeafShareNavigatioController ()

@end

@implementation SeafShareNavigatioController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Share Extension modal needs a solid opaque navigation bar.
    // Liquid Glass (configureWithDefaultBackground on iOS 26) renders as a
    // floating translucent pill, leaving the rest of the bar transparent.
    // Figma design: gradient #F1F1F1→#F9F9F9; we use #F9F9F9 as the solid fill.
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithOpaqueBackground];
        UIColor *navBarColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            if (tc.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor secondarySystemBackgroundColor];
            }
            return [UIColor colorWithRed:249.0/255.0 green:249.0/255.0 blue:249.0/255.0 alpha:1.0];
        }];
        appearance.backgroundColor = navBarColor;
        self.navigationBar.standardAppearance = appearance;
        self.navigationBar.scrollEdgeAppearance = appearance;
    }
}




- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
