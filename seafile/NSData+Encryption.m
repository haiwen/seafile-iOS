//
//  UIImage+FileType.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "NSData+Encryption.h"
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonKeyDerivation.h>


@implementation NSData (Encryption)

- (NSData *)AES128EncryptWithKey:(void *)key iv:(void *)iv option:(CCOptions)option
{
    NSUInteger dataLength = [self length];
    
    //See the doc: For block ciphers, the output size will always be less than or
    //equal to the input size plus the size of one block.
    //That's why we need to add the size of one block here
    size_t bufferSize = dataLength + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);
    
    size_t numBytesEncrypted = 0;
    CCCryptorStatus cryptStatus = CCCrypt(kCCEncrypt, kCCAlgorithmAES128, option,
                                          key, kCCKeySizeAES128,
                                          iv /* initialization vector (optional) */,
                                          [self bytes], dataLength, /* input */
                                          buffer, bufferSize, /* output */
                                          &numBytesEncrypted);
    if (cryptStatus == kCCSuccess) {
        //the returned NSData takes ownership of the buffer and will free it on deallocation
        return [NSData dataWithBytesNoCopy:buffer length:numBytesEncrypted];
    }
    
    free(buffer); //free the buffer;
    return nil;
}

- (NSData *)AES128DecryptWithKey:(void *)key iv:(void *)iv option:(CCOptions)option
{
    NSUInteger dataLength = [self length];
    
    //See the doc: For block ciphers, the output size will always be less than or
    //equal to the input size plus the size of one block.
    //That's why we need to add the size of one block here
    size_t bufferSize = dataLength + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);
    
    size_t numBytesDecrypted = 0;
    CCCryptorStatus cryptStatus = CCCrypt(kCCDecrypt, kCCAlgorithmAES128, option,
                                          key, kCCKeySizeAES128,
                                          iv /* initialization vector (optional) */,
                                          [self bytes], dataLength, /* input */
                                          buffer, bufferSize, /* output */
                                          &numBytesDecrypted);
    
    if (cryptStatus == kCCSuccess) {
        //the returned NSData takes ownership of the buffer and will free it on deallocation
        return [NSData dataWithBytesNoCopy:buffer length:numBytesDecrypted];
    }
    
    free(buffer); //free the buffer;
    return nil;
}

#if 0
- (CCOptions)generateKeyIv:(NSString *)password version:(int)version key:(uint8_t *)key iv:(uint8_t *)iv
{
    int rounds = 1 << 19;
    unsigned char salt[8] = { 0xda, 0x90, 0x45, 0xc3, 0x06, 0xc7, 0xcc, 0x26 };
    int saltlen = 8;
    CCOptions option = kCCOptionPKCS7Padding;
    if (version < 1) {
        option |= kCCOptionECBMode;
        rounds = 3;
        saltlen = 0;
    }
    bzero(iv, kCCKeySizeAES128);
    char passwordPtr[256]; // room for terminator (unused)
    bzero(passwordPtr, sizeof(passwordPtr)); // fill with zeroes (for padding)
    
    // fetch key data
    [password getCString:passwordPtr maxLength:sizeof(passwordPtr) encoding:NSUTF8StringEncoding];
    int ret = CCKeyDerivationPBKDF(kCCPBKDF2, passwordPtr, password.length, salt, saltlen, kCCPRFHmacAlgSHA1, rounds, key, kCCKeySizeAES128);
    NSAssert(ret == kCCSuccess, @"Unable to create AES key for password: %d", ret);
    return option;
}

- (NSData *)decrypt:(NSString *)password version:(int)version
{
    uint8_t key[kCCKeySizeAES128+1], iv[kCCKeySizeAES128+1];
    CCOptions option = [self generateKeyIv:password version:version key:key iv:iv];
    return [self AES128DecryptWithKey:key iv:NULL option:option];
}

- (NSData *)encrypt:(NSString *)password version:(int)version
{
    uint8_t key[kCCKeySizeAES128+1], iv[kCCKeySizeAES128+1];
    CCOptions option = [self generateKeyIv:password version:version key:key iv:iv];
    return [self AES128EncryptWithKey:key iv:iv option:option];
}
#else

#include <openssl/evp.h>

- (int)generateEncKey:(const char *)data_in inlen:(int)in_len version:(int)version key:(unsigned char *)key iv:(unsigned char *)iv
{
    unsigned char salt[8] = { 0xda, 0x90, 0x45, 0xc3, 0x06, 0xc7, 0xcc, 0x26 };
    if (version >= 1)
        return EVP_BytesToKey (EVP_aes_128_cbc(), /* cipher mode */
                               EVP_sha1(),        /* message digest */
                               salt,              /* salt */
                               (unsigned char*)data_in,
                               in_len,
                               1 << 19,   /* iteration times */
                               key, /* the derived key */
                               iv); /* IV, initial vector */
    else
        return EVP_BytesToKey (EVP_aes_128_ecb(), /* cipher mode */
                               EVP_sha1(),        /* message digest */
                               NULL,              /* salt */
                               (unsigned char*)data_in,
                               in_len,
                               3,   /* iteration times */
                               key, /* the derived key */
                               iv); /* IV, initial vector */
}

- (CCOptions)generateKeyIv:(NSString *)password version:(int)version key:(uint8_t *)key iv:(uint8_t *)iv
{
    CCOptions option = kCCOptionPKCS7Padding;
    if (version < 1) {
        option |= kCCOptionECBMode;
    }
    char passwordPtr[256]; // room for terminator (unused)
    bzero(passwordPtr, sizeof(passwordPtr)); // fill with zeroes (for padding)
    
    // fetch key data
    [password getCString:passwordPtr maxLength:sizeof(passwordPtr) encoding:NSUTF8StringEncoding];
    [self generateEncKey:passwordPtr inlen:password.length version:version key:key iv:iv];
    return option;
}

- (NSData *)decrypt:(NSString *)password version:(int)version
{
    uint8_t key[kCCKeySizeAES128+1], iv[kCCKeySizeAES128+1];
    CCOptions option = [self generateKeyIv:password version:version key:key iv:iv];
    return [self AES128DecryptWithKey:key iv:iv option:option];
}

- (NSData *)encrypt:(NSString *)password version:(int)version
{
    uint8_t key[kCCKeySizeAES128+1], iv[kCCKeySizeAES128+1];
    CCOptions option = [self generateKeyIv:password version:version key:key iv:iv];
    return [self AES128EncryptWithKey:key iv:iv option:option];
}

#endif

@end

