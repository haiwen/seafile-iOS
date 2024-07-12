//
//  UIImage+FileType.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIImage (FileType)

/**
 * Returns an image associated with a specific MIME type or file extension.
 * @param mimeType The MIME type for which an image representation is desired.
 * @param ext The file extension for which an image representation is desired.
 * @return An UIImage object representing the file type or nil if no suitable image is found.
 */
+ (UIImage *)imageForMimeType:(NSString *)mimeType ext:(NSString *)ext;

@end
