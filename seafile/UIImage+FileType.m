//
//  UIImage+FileType.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "UIImage+FileType.h"
#import "SKFileTypeImageLoader.h"

@implementation UIImage (FileType)

+ (UIImage *)imageForMimeType:(NSString *)mimeType
{
    return [SKFileTypeImageLoader imageForMimeType:mimeType];
};

@end
