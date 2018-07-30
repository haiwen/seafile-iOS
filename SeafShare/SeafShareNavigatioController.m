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
    // Do any additional setup after loading the view.
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    self.view.transform = CGAffineTransformMakeTranslation(0, self.view.bounds.size.height);
    [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationOptionAllowAnimatedContent | 7 << 16 animations:^{
        self.view.transform = CGAffineTransformIdentity;
    } completion:nil];
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
