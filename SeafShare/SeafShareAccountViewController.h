//
//  SeafShareAccountViewController.h
//  seafilePro
//
//  Created by three on 2018/8/2.
//  Copyright © 2018年 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>
@class SeafConnection;

typedef void(^SelectedConnBlock)(SeafConnection *conn);

@interface SeafShareAccountViewController : UIViewController

@property (nonatomic, copy) SelectedConnBlock selectedBlock;

@end
