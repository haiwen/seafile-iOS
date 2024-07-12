//
//  SecurityUtilities.h
//  seafilePro
//
//  Created by Wang Wei on 7/9/16.
//  Copyright © 2016 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/**
 * @class SecurityUtilities
 * @discussion This class contains methods to handle security operations
 */
@interface SecurityUtilities : NSObject

/**
 * Loads a certificate from a specified path and returns an identity reference and trust reference.
 * @param certificatePath The path to the certificate file.
 * @param keyPassword The password for the certificate, if needed.
 * @return A SecIdentityRef representing the identity extracted from the certificate file.
 */
+ (SecIdentityRef)copyIdentityAndTrustWithCertFile:(NSString *)certificatePath password:(NSString *)keyPassword;

/**
 * Saves a SecIdentityRef into the keychain and returns a persistent reference to the identity.
 * @param identity The identity to save.
 * @return A CFDataRef representing the persistent reference to the saved identity.
 */
+ (CFDataRef)saveSecIdentity:(SecIdentityRef)identity;

/**
 * Retrieves a SecIdentityRef using a persistent reference.
 * @param persistentRef The persistent reference to the identity.
 * @return A SecIdentityRef representing the identity associated with the given persistent reference.
 */
+ (SecIdentityRef)getSecIdentityForPersistentRef:(CFDataRef)persistentRef;

/**
 * Removes a SecIdentityRef associated with a persistent reference from the keychain.
 * @param identity The identity to remove.
 * @param persistentRef The persistent reference to the identity.
 * @return A BOOL indicating success or failure.
 */
+ (BOOL)removeIdentity:(SecIdentityRef)identity forPersistentRef:(CFDataRef)persistentRef;

/**
 * Retrieves a human-readable name for the given identity.
 * @param identity The identity to get the name for.
 * @return A NSString representing the name of the identity.
 */
+(NSString *)nameForIdentity:(SecIdentityRef)identity;

/**
 * Creates a NSURLCredential from a given SecIdentityRef.
 * @param identity The identity to create the credential from.
 * @return A NSURLCredential created from the given identity.
 */
+ (NSURLCredential *)getCredentialFromSecIdentity:(SecIdentityRef)identity;

/**
 * Loads a certificate from a file and creates a NSURLCredential.
 * @param certificatePath The path to the certificate file.
 * @param keyPassword The password for the certificate.
 * @return A NSURLCredential created from the certificate file.
 */
+ (NSURLCredential *)getCredentialFromFile:(NSString *)certificatePath password:(NSString *)keyPassword;

/**
 * Lists all the security items of specified classes in the keychain.
 */
+ (void)showAll;

@end

