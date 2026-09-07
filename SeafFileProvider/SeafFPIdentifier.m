//
//  SeafFPIdentifier.m
//  SeafFileProvider
//

#import "SeafFPIdentifier.h"
#import "SeafConstants.h"
#import <FileProvider/FileProvider.h>
#import <CommonCrypto/CommonDigest.h>

static NSString * const kSeafFPRepoPrefix = @"r:";
static NSString * const kSeafFPItemPrefix = @"i:";
static NSString * const kSeafFPDomainPrefix = @"acct-";
static NSString * const kSeafFPStoreDirectory = @"fileprovider";

@implementation SeafFPIdentifier

+ (SeafFPIdentifierKind)kindOfIdentifier:(NSString *)identifier
{
    if (identifier.length == 0) return SeafFPIdentifierKindUnknown;
    if ([identifier isEqualToString:NSFileProviderRootContainerItemIdentifier]) return SeafFPIdentifierKindRoot;
    if ([identifier isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier]) return SeafFPIdentifierKindWorkingSet;
    if ([identifier isEqualToString:NSFileProviderTrashContainerItemIdentifier]) return SeafFPIdentifierKindTrash;
    if ([identifier hasPrefix:kSeafFPRepoPrefix] && identifier.length > kSeafFPRepoPrefix.length) return SeafFPIdentifierKindRepo;
    if ([identifier hasPrefix:kSeafFPItemPrefix] && identifier.length > kSeafFPItemPrefix.length) return SeafFPIdentifierKindItem;
    return SeafFPIdentifierKindUnknown;
}

+ (NSString *)identifierForRepo:(NSString *)repoId
{
    return [kSeafFPRepoPrefix stringByAppendingString:repoId];
}

+ (NSString *)identifierForUUID:(NSString *)uuid
{
    return [kSeafFPItemPrefix stringByAppendingString:uuid];
}

+ (NSString *)repoIdFromIdentifier:(NSString *)identifier
{
    if ([self kindOfIdentifier:identifier] != SeafFPIdentifierKindRepo) return nil;
    return [identifier substringFromIndex:kSeafFPRepoPrefix.length];
}

+ (NSString *)uuidFromIdentifier:(NSString *)identifier
{
    if ([self kindOfIdentifier:identifier] != SeafFPIdentifierKindItem) return nil;
    return [identifier substringFromIndex:kSeafFPItemPrefix.length];
}

+ (NSString *)newUUID
{
    return [[[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
}

+ (NSString *)normalizedPath:(NSString *)path
{
    NSString *p = path.precomposedStringWithCanonicalMapping ?: @"";
    while ([p containsString:@"//"]) {
        p = [p stringByReplacingOccurrencesOfString:@"//" withString:@"/"];
    }
    if (![p hasPrefix:@"/"]) {
        p = [@"/" stringByAppendingString:p];
    }
    while (p.length > 1 && [p hasSuffix:@"/"]) {
        p = [p substringToIndex:p.length - 1];
    }
    return p;
}

+ (NSString *)normalizedAddress:(NSString *)address
{
    NSString *a = address ?: @"";
    while ([a hasSuffix:@"/"]) {
        a = [a substringToIndex:a.length - 1];
    }
    return a;
}

+ (NSString *)domainIdentifierForAddress:(NSString *)address username:(NSString *)username
{
    NSString *seed = [NSString stringWithFormat:@"%@\n%@", [self normalizedAddress:address], username ?: @""];
    return [kSeafFPDomainPrefix stringByAppendingString:[[self sha1Hex:seed] substringToIndex:16]];
}

+ (BOOL)isSeafileDomainIdentifier:(NSString *)identifier
{
    return [identifier hasPrefix:kSeafFPDomainPrefix];
}

+ (NSData *)versionComponentData:(NSString *)string
{
    static const NSUInteger kComponentMaxLength = 128;
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length > kComponentMaxLength) {
        data = [[self sha1Hex:string] dataUsingEncoding:NSUTF8StringEncoding];
    }
    return data;
}

+ (NSString *)sha1Hex:(NSString *)string
{
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

+ (NSURL *)storeDirectoryURL
{
    NSURL *group = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:SEAFILE_SUITE_NAME];
    return [group URLByAppendingPathComponent:kSeafFPStoreDirectory isDirectory:YES];
}

+ (NSURL *)storeURLForDomainIdentifier:(NSString *)domainIdentifier
{
    NSString *name = [domainIdentifier stringByAppendingPathExtension:@"sqlite"];
    return [[self storeDirectoryURL] URLByAppendingPathComponent:name isDirectory:NO];
}

@end
