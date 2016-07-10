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

+ (NSArray *)getKeyChainCredentials;
+ (BOOL)importCertToKeyChain:(NSString *)certificatePath password:(NSString *)keyPassword;
+ (BOOL)removeIdentityFromKeyChain:(SecIdentityRef)identity;
+ (SecIdentityRef)getSecIdentityFromKeyChain:(NSString *)certName;
+ (NSURLCredential *)getCredentialFromSecIdentity:(SecIdentityRef)identity;
+ (void)chooseCertFrom:(NSArray *)certs handler:(void (^)(SecIdentityRef identity))completeHandler from:(UIViewController *)c;

@end
