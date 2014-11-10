//
//  FileMimeType.h
//  seafile
//
//  Created by Wang Wei on 10/17/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FileMimeType : NSObject

+ (NSString *)mimeType:(NSString *)fileName;

@end
