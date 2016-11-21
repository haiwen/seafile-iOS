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

#import "Debug.h"
#define ENC_SUCCESS 1
#define ENC_FAILURE 0
#define DEC_SUCCESS 1
#define DEC_FAILURE 0
#define BLK_SIZE 16


void
rawdata_to_hex (const unsigned char *rawdata, char *hex_str, int n_bytes)
{
    static const char hex[] = "0123456789abcdef";
    int i;

    for (i = 0; i < n_bytes; i++) {
        unsigned int val = *rawdata++;
        *hex_str++ = hex[val >> 4];
        *hex_str++ = hex[val & 0xf];
    }
    *hex_str = '\0';
}

static unsigned hexval(char c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return ~0;
}

int
hex_to_rawdata (const char *hex_str, char *rawdata, int n_bytes)
{
    int i;
    for (i = 0; i < n_bytes; i++) {
        unsigned int val = (hexval(hex_str[0]) << 4) | hexval(hex_str[1]);
        if (val & ~0xff)
            return -1;
        *rawdata++ = val;
        hex_str += 2;
    }
    return 0;
}
#include <openssl/evp.h>

@implementation NSData (Encryption)



+ (int)deriveKey:(const char *)data_in inlen:(int)in_len version:(int)version key:(unsigned char *)key iv:(unsigned char *)iv
{
    unsigned char salt[8] = { 0xda, 0x90, 0x45, 0xc3, 0x06, 0xc7, 0xcc, 0x26 };
    if (version == 2) {
        PKCS5_PBKDF2_HMAC (data_in, in_len,
                           salt, sizeof(salt),
                           1000,
                           EVP_sha256(),
                           32, key);
        PKCS5_PBKDF2_HMAC ((char *)key, 32,
                           salt, sizeof(salt),
                           10,
                           EVP_sha256(),
                           16, iv);
        return 0;
    } else if (version == 1)
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

+(int)seafileDecrypt:(char *)data_out outlen:(int *)out_len datain:(const char *)data_in inlen:(const int)in_len version:(int)version key:(uint8_t *)key iv:(uint8_t *)iv
{
    int ret;
    EVP_CIPHER_CTX ctx;
    EVP_CIPHER_CTX_init (&ctx);
    if (version == 2)
        ret = EVP_DecryptInit_ex (&ctx,
                                  EVP_aes_256_cbc(), /* cipher mode */
                                  NULL, /* engine, NULL for default */
                                  key,  /* derived key */
                                  iv);  /* initial vector */
    else if (version == 1)
        ret = EVP_DecryptInit_ex (&ctx,
                                  EVP_aes_128_cbc(), /* cipher mode */
                                  NULL, /* engine, NULL for default */
                                  key,  /* derived key */
                                  iv);  /* initial vector */
    else
        ret = EVP_DecryptInit_ex (&ctx,
                                  EVP_aes_128_ecb(), /* cipher mode */
                                  NULL, /* engine, NULL for default */
                                  key,  /* derived key */
                                  iv);  /* initial vector */
    if (ret == DEC_FAILURE)
        return -1;

    int update_len, final_len;

    /* Do the decryption. */
    ret = EVP_DecryptUpdate (&ctx,
                             (unsigned char*)data_out,
                             &update_len,
                             (unsigned char*)data_in,
                             in_len);

    if (ret == DEC_FAILURE)
        goto dec_error;

    /* Finish the possible partial block. */
    ret = EVP_DecryptFinal_ex (&ctx,
                               (unsigned char*)data_out + update_len,
                               &final_len);
    *out_len = update_len + final_len;

    if (ret == DEC_FAILURE || *out_len > in_len)
        goto dec_error;

    EVP_CIPHER_CTX_cleanup (&ctx);
    return 0;

dec_error:

    EVP_CIPHER_CTX_cleanup (&ctx);

    *out_len = -1;
    return -1;
}

+(int)seafileEncrypt:(char **)data_out outlen:(int *)out_len datain:(const char *)data_in inlen:(const int)in_len version:(int)version key:(uint8_t *)key iv:(uint8_t *)iv
{
    int ret, blks;
    EVP_CIPHER_CTX ctx;
    EVP_CIPHER_CTX_init (&ctx);
    if (version == 2)
        ret = EVP_EncryptInit_ex (&ctx,
                                  EVP_aes_256_cbc(), /* cipher mode */
                                  NULL, /* engine, NULL for default */
                                  key,  /* derived key */
                                  iv);  /* initial vector */
    else if (version == 1)
        ret = EVP_EncryptInit_ex (&ctx,
                                  EVP_aes_128_cbc(), /* cipher mode */
                                  NULL, /* engine, NULL for default */
                                  key,  /* derived key */
                                  iv);  /* initial vector */
    else
        ret = EVP_EncryptInit_ex (&ctx,
                                  EVP_aes_128_ecb(), /* cipher mode */
                                  NULL, /* engine, NULL for default */
                                  key,  /* derived key */
                                  iv);  /* initial vector */
    if (ret == DEC_FAILURE)
        return -1;

    blks = (in_len / BLK_SIZE) + 1;
    *data_out = (char *)malloc (blks * BLK_SIZE);
    if (*data_out == NULL) {
        Debug ("failed to allocate the output buffer.\n");
        goto enc_error;
    }
    int update_len, final_len;

    /* Do the encryption. */
    ret = EVP_EncryptUpdate (&ctx,
                             (unsigned char*)*data_out,
                             &update_len,
                             (unsigned char*)data_in,
                             in_len);

    if (ret == ENC_FAILURE)
        goto enc_error;


    /* Finish the possible partial block. */
    ret = EVP_EncryptFinal_ex (&ctx,
                               (unsigned char*)*data_out + update_len,
                               &final_len);

    *out_len = update_len + final_len;

    /* out_len should be equal to the allocated buffer size. */
    if (ret == ENC_FAILURE || *out_len != (blks * BLK_SIZE))
        goto enc_error;

    EVP_CIPHER_CTX_cleanup (&ctx);

    return 0;

enc_error:
    EVP_CIPHER_CTX_cleanup (&ctx);
    *out_len = -1;

    if (*data_out != NULL)
        free (*data_out);

    *data_out = NULL;

    return -1;
}

+ (void)generateKey:(NSString *)password version:(int)version encKey:(NSString *)encKey key:(uint8_t *)key iv:(uint8_t *)iv
{
    unsigned char key0[32], iv0[16];
    char passwordPtr[256] = {0}; // room for terminator (unused)
    [password getCString:passwordPtr maxLength:sizeof(passwordPtr) encoding:NSUTF8StringEncoding];
    if (version < 2) {
        [NSData deriveKey:passwordPtr inlen:(int)password.length version:version key:key iv:iv];
        return;
    }
    [NSData deriveKey:passwordPtr inlen:(int)password.length version:version key:key0 iv:iv0];
    char enc_random_key[48], dec_random_key[48];
    int outlen;
    hex_to_rawdata(encKey.UTF8String, enc_random_key, 48);
    [NSData seafileDecrypt:dec_random_key outlen:&outlen datain:(char *)enc_random_key inlen:48 version:2 key:key0 iv:iv0];
    [NSData deriveKey:dec_random_key inlen:32 version:2 key:key iv:iv];
}

- (NSData *)decrypt:(NSString *)password encKey:(NSString *)encKey version:(int)version
{
    uint8_t key[kCCKeySizeAES256+1] = {0}, iv[kCCKeySizeAES128+1];
    [NSData generateKey:password version:version encKey:encKey key:key iv:iv];
    char *data_out = malloc(self.length);
    int outlen;
    int ret = [NSData seafileDecrypt:data_out outlen:&outlen datain:self.bytes inlen:(int)self.length version:version key:key iv:iv];
    if (ret < 0) {
        free (data_out);
        return nil;
    }
    return [NSData dataWithBytesNoCopy:data_out length:outlen];
}

- (NSData *)encrypt:(NSString *)password encKey:(NSString *)encKey version:(int)version
{
    uint8_t key[kCCKeySizeAES256+1] = {0}, iv[kCCKeySizeAES128+1];
    [NSData generateKey:password version:version encKey:encKey key:key iv:iv];
    char *data_out;
    int outlen;
    int ret = [NSData seafileEncrypt:&data_out outlen:&outlen datain:self.bytes inlen:(int)self.length version:version key:key iv:iv];
    if (ret < 0) return nil;
    return [NSData dataWithBytesNoCopy:data_out length:outlen];
}

+ (NSString *)passwordMaigc:(NSString *)password repo:(NSString *)repoId version:(int)version
{
    uint8_t key[kCCKeySizeAES256+1], iv[kCCKeySizeAES128+1];
    char res[kCCKeySizeAES256*2+1] = { 0 };
    NSString *s = [repoId stringByAppendingString:password];
    char passwordPtr[256] = {0}; // room for terminator (unused)
    [s getCString:passwordPtr maxLength:sizeof(passwordPtr) encoding:NSUTF8StringEncoding];
    [NSData deriveKey:passwordPtr inlen:(int)s.length version:version key:key iv:iv];
    if (version == 2)
        rawdata_to_hex(key, res, kCCKeySizeAES256);
    else
        rawdata_to_hex(key, res, kCCKeySizeAES128);
    Debug("version=%d, magic=%s", version, res);
    return [NSString stringWithUTF8String:res];
}

- (NSString *)SHA1
{
    unsigned char sha1[20];
    char hex[41];
    hex[40] = '\0';
    CC_SHA1(self.bytes, (int)self.length, sha1);
    rawdata_to_hex(sha1, hex, 20);
    return [NSString stringWithUTF8String:hex];
}

- (NSString *)hexString
{
#define HEX_MAXLEN 512
    char hex[HEX_MAXLEN*2 +1];
    int len = (int)self.length;
    if (len == 0) return @"";
    if (len > HEX_MAXLEN) len = HEX_MAXLEN;
    rawdata_to_hex(self.bytes, hex, len);
    hex[len*2] = '\0';
    return [NSString stringWithUTF8String:hex];
}


@end

