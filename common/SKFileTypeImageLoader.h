//
//  SKFileTypeImageLoader.h
//  SparkleShare
//
//  Created by Sergey Klimov on 16.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface SKFileTypeImageLoader : NSObject
{
    NSMutableDictionary *images;
}

@property (retain) NSDictionary* config;

+ (UIImage *)imageForMimeType:(NSString *)mimeType;
+ (UIImage *)imageForMimeType:(NSString *)mimeType ext:(NSString *)ext;


@end
