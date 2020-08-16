//
//  SeafInputItemsProvider.h
//  seafilePro
//
//  Created by three on 2018/8/16.
//  Copyright © 2018年 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^CompleteBlock)(BOOL result, NSArray *array);
typedef void(^ItemLoadHandler)(BOOL result);

@interface SeafInputItemsProvider : NSObject

+ (void)loadInputs:(NSExtensionContext *)extensionContext complete:(CompleteBlock)block;

@end
