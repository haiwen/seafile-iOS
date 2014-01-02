//
//  NSData_Encryption.h
//  seafilePro
//
//  Created by Wang Wei on 8/4/13.
//  Copyright (c) 2013 tsinghua. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (Encryption)

- (NSData *)decrypt:(NSString *)password encKey:(NSString *)encKey version:(int)version;
- (NSData *)encrypt:(NSString *)password encKey:(NSString *)encKey version:(int)version;
- (NSString *)SHA1;

+ (NSString *)passwordMaigc:(NSString *)password repo:(NSString *)repoId version:(int)version;

- (NSString *)hexString;

@end
