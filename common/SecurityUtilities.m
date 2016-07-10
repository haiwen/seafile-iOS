//
//  SecurityUtilites.m
//  seafilePro
//
//  Created by Wang Wei on 7/9/16.
//  Copyright © 2016 Seafile. All rights reserved.
//

#import "SecurityUtilities.h"
#import "Debug.h"

@implementation SecurityUtilities

+ (NSArray *)getKeyChainCredentials
{
    NSMutableDictionary *searchDictionary = [[NSMutableDictionary alloc] init];
    [searchDictionary setObject:(id)kSecClassIdentity forKey:(id)kSecClass];
    [searchDictionary setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes];
    [searchDictionary setObject:(id)kSecMatchLimitAll forKey:(id)kSecMatchLimit];

    CFTypeRef result = NULL;
    OSStatus searchStatus = SecItemCopyMatching((__bridge CFDictionaryRef)searchDictionary, &result);
    if (searchStatus != errSecSuccess) {
        Warning("Couldn't find the cert ref: %d", (int)searchStatus);
        return nil;
    }

    return (__bridge NSArray *)(result);
}

+ (SecIdentityRef)getSecIdentityFromKeyChain:(NSString *)certName
{
    if (!certName)
        return nil;
    NSMutableDictionary *searchDictionary = [[NSMutableDictionary alloc] init];
    [searchDictionary setObject:(id)kSecClassIdentity forKey:(id)kSecClass];
    [searchDictionary setObject:certName forKey:(id)kSecAttrLabel];
    [searchDictionary setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnRef];

    NSData *queryResult = nil;
    OSStatus searchStatus = SecItemCopyMatching((__bridge CFDictionaryRef)searchDictionary, (void *)&queryResult);

    if (searchStatus != errSecSuccess) {
        Warning("Couldn't find the cert ref: %d", (int)searchStatus);
        return nil;
    }

    SecIdentityRef identity = (__bridge SecIdentityRef)queryResult;
    return identity;
}

+ (NSURLCredential *)getCredentialFromSecIdentity:(SecIdentityRef)identity
{
#if 0
    SecCertificateRef certificateRef = NULL;
    SecIdentityCopyCertificate(identity, &certificateRef);

    NSArray *certificateArray = [[NSArray alloc] initWithObjects:(__bridge_transfer id)(certificateRef), nil];
    NSURLCredentialPersistence persistence = NSURLCredentialPersistenceForSession;

    NSURLCredential *credential = [[NSURLCredential alloc] initWithIdentity:identity
                                                               certificates:certificateArray
                                                                persistence:persistence];

    return credential;
#else
    return [NSURLCredential credentialWithIdentity:identity
                                      certificates:nil
                                       persistence:NSURLCredentialPersistencePermanent];
#endif
}

+ (BOOL)importCertToKeyChain:(NSString *)certificatePath password:(NSString *)keyPassword
{
    SecIdentityRef identity = [SecurityUtilities copyIdentityAndTrustWithCertFile:certificatePath password:keyPassword];
    if (!identity)
        return false;
    [SecurityUtilities persistentRefForIdentity:identity];
    return true;
}

+ (void)persistentRefForIdentity:(SecIdentityRef) identity
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
}

+ (BOOL)removeIdentityFromKeyChain:(SecIdentityRef)identity
{
    OSStatus status = errSecSuccess;
    NSDictionary *query = @{ (id)kSecValueRef:(__bridge NSData *)identity,
                             (id)kSecClass:(id)kSecClassCertificate};

    status = SecItemDelete((CFDictionaryRef)query);
    return (status == errSecSuccess);
}


+(void)chooseCertFrom:(NSArray *)certs handler:(void (^)(SecIdentityRef identity))completeHandler from:(UIViewController *)c
{
    NSString *title = NSLocalizedString(@"Select a certificate", @"Seafile");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];

    for (NSDictionary *dict in certs) {
        NSString *label = [dict objectForKey:(id)kSecAttrLabel];
        NSString *group = [dict objectForKey:(id)kSecAttrAccessGroup];
        NSString *name = [NSString stringWithFormat:@"%@ (%@)", label, group];
        UIAlertAction *action = [UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            completeHandler([SecurityUtilities getSecIdentityFromKeyChain:label]);
        }];
        [alert addAction:action];
    }
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:STR_CANCEL style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        completeHandler(nil);
    }];
    [alert addAction:cancelAction];
    [c presentViewController:alert animated:YES completion:nil];
}

+ (NSURLCredential *)getCredentialFromFile:(NSString *)certificatePath password:(NSString *)keyPassword
{
    SecIdentityRef identity = [SecurityUtilities copyIdentityAndTrustWithCertFile:certificatePath password:keyPassword];
    return [SecurityUtilities getCredentialFromSecIdentity:identity];
}

+ (SecIdentityRef)copyIdentityAndTrustWithCertFile:(NSString *)certificatePath password:(NSString *)keyPassword
{
    NSData *PKCS12Data = [NSData dataWithContentsOfFile:certificatePath];
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

