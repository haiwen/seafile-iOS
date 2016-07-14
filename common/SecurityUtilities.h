//
//  SecurityUtilities.h
//  seafilePro
//
//  Created by Wang Wei on 7/9/16.
//  Copyright © 2016 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface SecurityUtilities : NSObject


+ (SecIdentityRef)copyIdentityAndTrustWithCertFile:(NSString *)certificatePath password:(NSString *)keyPassword;
+ (CFDataRef)saveSecIdentity:(SecIdentityRef)identity;

+ (SecIdentityRef)getSecIdentityForPersistentRef:(CFDataRef)persistentRef;
+ (BOOL)removeIdentity:(SecIdentityRef)identity forPersistentRef:(CFDataRef)persistentRef;

+(NSString *)nameForIdentity:(SecIdentityRef)identity;

+ (NSURLCredential *)getCredentialFromSecIdentity:(SecIdentityRef)identity;

+ (NSURLCredential *)getCredentialFromFile:(NSString *)certificatePath password:(NSString *)keyPassword;

+ (void)showAll;

@end

