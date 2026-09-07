//
//  SeafFPIdentifier.h
//  SeafFileProvider
//
//  Item identifier, path, and domain identifier conventions shared by the
//  main app and the replicated File Provider extension. Pure Foundation.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SeafFPIdentifierKind) {
    SeafFPIdentifierKindUnknown = 0,
    SeafFPIdentifierKindRoot,        // NSFileProviderRootContainerItemIdentifier: library list
    SeafFPIdentifierKindRepo,        // r:<repoId>
    SeafFPIdentifierKindItem,        // i:<uuid>
    SeafFPIdentifierKindWorkingSet,  // NSFileProviderWorkingSetContainerItemIdentifier
    SeafFPIdentifierKindTrash,       // NSFileProviderTrashContainerItemIdentifier
};

@interface SeafFPIdentifier : NSObject

+ (SeafFPIdentifierKind)kindOfIdentifier:(nullable NSString *)identifier;

+ (NSString *)identifierForRepo:(NSString *)repoId;
+ (NSString *)identifierForUUID:(NSString *)uuid;
+ (nullable NSString *)repoIdFromIdentifier:(nullable NSString *)identifier;
+ (nullable NSString *)uuidFromIdentifier:(nullable NSString *)identifier;

/// 32 lowercase hex characters, no dashes.
+ (NSString *)newUUID;

/// Leading slash, no trailing slash (root is "/"), no duplicate slashes, NFC.
+ (NSString *)normalizedPath:(nullable NSString *)path;

/// Same rule as SeafGlobal getConnection:/saveConnection: strip trailing
/// slashes only. Case and scheme are left untouched on purpose.
+ (NSString *)normalizedAddress:(nullable NSString *)address;

/// "acct-" + first 16 hex chars of SHA1(normalizedAddress + "\n" + username).
+ (NSString *)domainIdentifierForAddress:(nullable NSString *)address username:(nullable NSString *)username;
+ (BOOL)isSeafileDomainIdentifier:(nullable NSString *)identifier;

+ (NSString *)sha1Hex:(NSString *)string;

/// UTF-8 of `string` as an NSFileProviderItemVersion component. Components
/// are limited to 128 bytes (NSFileProviderItemVersion.h) and the initializer
/// does not check: a longer string is replaced by its SHA1 hex digest, a
/// shorter one keeps its bytes so existing versions stay unchanged.
+ (NSData *)versionComponentData:(NSString *)string;

/// <App Group>/fileprovider
+ (NSURL *)storeDirectoryURL;
/// <App Group>/fileprovider/<domainIdentifier>.sqlite
+ (NSURL *)storeURLForDomainIdentifier:(NSString *)domainIdentifier;

@end

NS_ASSUME_NONNULL_END
