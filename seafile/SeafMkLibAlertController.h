//
//  SeafMkLibAlertController.h
//  seafileApp
//
//  Created by three on 2018/4/14.
//  Copyright © 2018年 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef void(^HandlerBlock)(NSString *name, NSString *pwd);

@interface SeafMkLibAlertController : UIViewController

@property (nonatomic, copy) HandlerBlock handlerBlock;

@end
