//
//  SecurityUtilites.m
//  seafilePro
//
//  Created by Wang Wei on 7/9/16.
//  Copyright © 2016 Seafile. All rights reserved.
//

#import "SecurityUtilities.h"
#import "Debug.h"

static NSString *copySummaryString(SecIdentityRef identity)
{
    // Get the certificate from the identity.
    SecCertificateRef myReturnedCertificate = NULL;
    OSStatus status = SecIdentityCopyCertificate (identity,
                                                  &myReturnedCertificate);  // 1

    if (status) {
        Debug("SecIdentityCopyCertificate failed.\n");
        return NULL;
    }

    CFStringRef certSummary = SecCertificateCopySubjectSummary
    (myReturnedCertificate);  // 2

    NSString* summaryString = [[NSString alloc]
                               initWithString:(__bridge NSString *)certSummary];  // 3

    CFRelease(certSummary);
    Debug("summaryString: %@", summaryString);
    return summaryString;
}

static CFDataRef getPersistentRefForIdentity(SecIdentityRef identity)
{
    OSStatus status = errSecSuccess;

    CFTypeRef  persistent_ref = NULL;
    const void *keys[] =   { kSecReturnPersistentRef, kSecValueRef };
    const void *values[] = { kCFBooleanTrue,          identity };
    CFDictionaryRef dict = CFDictionaryCreate(NULL, keys, values,
                                              2, NULL, NULL);
    status = SecItemCopyMatching(dict, &persistent_ref);

    if (dict)
        CFRelease(dict);

    Debug("status=%d persistent_ref=%@", (int)status, persistent_ref);
    if (status != errSecSuccess)
        return nil;
    return (CFDataRef)persistent_ref;
}

static CFDataRef persistentRefForIdentity(SecIdentityRef identity)
{
    OSStatus status = errSecSuccess;

    CFTypeRef  persistent_ref = NULL;
    const void *keys[] =   { kSecReturnPersistentRef, kSecValueRef };
    const void *values[] = { kCFBooleanTrue,          identity };
    CFDictionaryRef dict = CFDictionaryCreate(NULL, keys, values,
                                              2, NULL, NULL);
    status = SecItemAdd(dict, &persistent_ref);

    if (dict)
        CFRelease(dict);
    Debug("status=%d persistent_ref=%@", (int)status, persistent_ref);
    if (status == errSecDuplicateItem) {
        Warning("Identity already exists.");
        return getPersistentRefForIdentity(identity);
    }
    if (status != errSecSuccess)
        return nil;
    return (CFDataRef)persistent_ref;
}

static SecIdentityRef identityForPersistentRef(CFDataRef persistent_ref)
{
    CFTypeRef   identity_ref     = NULL;
    const void *keys[] =   { kSecClass, kSecReturnRef,  kSecValuePersistentRef };
    const void *values[] = { kSecClassIdentity, kCFBooleanTrue, persistent_ref };
    CFDictionaryRef dict = CFDictionaryCreate(NULL, keys, values,
                                              3, NULL, NULL);
    OSStatus status __attribute__((unused)) = SecItemCopyMatching(dict, &identity_ref);

    if (dict)
        CFRelease(dict);
    Debug("status=%d", (int)status);
    return (SecIdentityRef)identity_ref;
}

static BOOL removeIdentityForPersistentRef(CFDataRef persistent_ref)
{
    NSDictionary *query = @{ (id)kSecValuePersistentRef: (__bridge id)persistent_ref };
    OSStatus status = SecItemDelete((CFDictionaryRef)query);
    Debug("status=%d", (int)status);
    return status == errSecSuccess;
}

@implementation SecurityUtilities

+ (void)showAll {
    NSMutableDictionary *query = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                  (__bridge id)kCFBooleanTrue, (__bridge id)kSecReturnAttributes,
                                  (__bridge id)kSecMatchLimitAll, (__bridge id)kSecMatchLimit,
                                  nil];
    NSArray *secItemClasses = [NSArray arrayWithObjects:
                               (__bridge id)kSecClassGenericPassword,
                               (__bridge id)kSecClassInternetPassword,
                               (__bridge id)kSecClassCertificate,
                               (__bridge id)kSecClassKey,
                               (__bridge id)kSecClassIdentity,
                               nil];
    for (id secItemClass in secItemClasses) {
        [query setObject:secItemClass forKey:(__bridge id)kSecClass];

        CFTypeRef result = NULL;
        OSStatus status __attribute__((unused)) = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        Debug("%@, status:%d, %@", secItemClass, (int)status,  (__bridge id)result);
        if (result != NULL) CFRelease(result);
    }
}

+ (CFDataRef)saveSecIdentity:(SecIdentityRef)identity
{
    return persistentRefForIdentity(identity);
}

+ (SecIdentityRef)getSecIdentityForPersistentRef:(CFDataRef)persistentRef
{
    return identityForPersistentRef(persistentRef);
}

+ (BOOL)removeIdentity:(SecIdentityRef)identity forPersistentRef:(CFDataRef)persistentRef
{
    return removeIdentityForPersistentRef(persistentRef);
}

+(NSString *)nameForIdentity:(SecIdentityRef)identity
{
    return copySummaryString(identity);
}

+ (NSURLCredential *)getCredentialFromSecIdentity:(SecIdentityRef)identity
{
    if (!identity)
        return nil;

    SecCertificateRef certificateRef = NULL;
    SecIdentityCopyCertificate(identity, &certificateRef);

    NSArray *certificateArray = nil;
    if (!certificateRef)
        certificateArray = [[NSArray alloc] initWithObjects:(__bridge_transfer id)(certificateRef), nil];
    NSURLCredential *cred = [NSURLCredential credentialWithIdentity:identity
                                                       certificates:certificateArray
                                                        persistence:NSURLCredentialPersistencePermanent];
    return cred;
}

+ (NSURLCredential *)getCredentialFromFile:(NSString *)certificatePath password:(NSString *)keyPassword
{
    SecIdentityRef identity = [SecurityUtilities copyIdentityAndTrustWithCertFile:certificatePath password:keyPassword];
    return [SecurityUtilities getCredentialFromSecIdentity:identity];
}

+ (SecIdentityRef)copyIdentityAndTrustWithCertFile:(NSString *)certificatePath password:(NSString *)keyPassword
{
    NSData *PKCS12Data = [NSData dataWithContentsOfFile:certificatePath];
    if (!PKCS12Data) {
        Warning("Failed to read cert content file exist: %d", [[NSFileManager defaultManager] fileExistsAtPath:certificatePath]);
        return nil;
    }
    return [SecurityUtilities copyIdentityAndTrustWithCertData:(CFDataRef)PKCS12Data password:(CFStringRef)keyPassword];
}

+ (SecIdentityRef)copyIdentityAndTrustWithCertData:(CFDataRef)inPKCS12Data password:(CFStringRef)keyPassword
{
    SecIdentityRef extractedIdentity = nil;
    OSStatus securityError = errSecSuccess;

    const void *keys[] = {kSecImportExportPassphrase};
    const void *values[] = {keyPassword};
    CFDictionaryRef optionsDictionary = NULL;

    optionsDictionary = CFDictionaryCreate(NULL, keys, values, (keyPassword ? 1 : 0), NULL, NULL);

    CFArrayRef items = NULL;
    securityError = SecPKCS12Import(inPKCS12Data, optionsDictionary, &items);

    if (securityError == errSecSuccess) {
        CFDictionaryRef myIdentityAndTrust = CFArrayGetValueAtIndex(items, 0);

        // get identity from dictionary
        extractedIdentity = (SecIdentityRef)CFDictionaryGetValue(myIdentityAndTrust, kSecImportItemIdentity);
        CFRetain(extractedIdentity);
    }

    if (optionsDictionary) {
        CFRelease(optionsDictionary);
    }

    if (items) {
        CFRelease(items);
    }

    return extractedIdentity;
}

@end

