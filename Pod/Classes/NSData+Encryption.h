//
//  NSData_Encryption.h
//  seafilePro
//
//  Created by Wang Wei on 8/4/13.
//  Copyright (c) 2013 tsinghua. All rights reserved.
//

#import <Foundation/Foundation.h>
/**
    Category on NSData to add encryption and decryption functionalities, alongside other cryptographic utilities.
 */
@interface NSData (Encryption)

/**
 * Decrypts data using the specified password, encryption key, and version.
 * @param password The password used for decryption.
 * @param encKey The encryption key used.
 * @param version The version of the encryption algorithm.
 * @return The decrypted version of the NSData, or nil if decryption fails.
 */
- (NSData *)decrypt:(NSString *)password encKey:(NSString *)encKey version:(int)version;

/**
 * Encrypts data using the specified password, encryption key, and version.
 * @param password The password used for encryption.
 * @param encKey The encryption key used.
 * @param version The version of the encryption algorithm.
 * @return The encrypted version of the NSData, or nil if encryption fails.
 */
- (NSData *)encrypt:(NSString *)password encKey:(NSString *)encKey version:(int)version;

/**
 * Computes the SHA-1 hash of this data instance.
 * @return A string representing the SHA-1 hash of the data.
 */
- (NSString *)SHA1;

/**
 * Generates a password hash used within the application, combining repository ID and password.
 * @param password The password to hash.
 * @param repoId The repository identifier to combine with the password.
 * @param version The version of the cryptographic operations.
 * @return A string representing the hashed password.
 */
+ (NSString *)passwordMaigc:(NSString *)password repo:(NSString *)repoId version:(int)version;

/**
 * Converts the NSData into a hexadecimal string.
 * @return A hexadecimal string representation of the NSData.
 */
- (NSString *)hexString;

@end
