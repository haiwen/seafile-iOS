//
//  SeafFPErrors.h
//  SeafFileProvider
//
//  Seafile / network errors mapped to NSFileProviderErrorDomain.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// userInfo key carried to the FPUIActionExtension so it can pick a message.
extern NSString * const SeafFPErrorReasonKey;
extern NSString * const SeafFPErrorReasonNotAuthenticated;
extern NSString * const SeafFPErrorReasonNoAccount;
FOUNDATION_EXPORT NSString * const SeafFPErrorReasonTouchIdEnabled;

@interface SeafFPErrors : NSObject

+ (NSError *)serverUnreachable;
+ (NSError *)notAuthenticated;
+ (NSError *)noAccount;
/// The account is protected by Face ID / Touch ID; Files must not show it.
+ (NSError *)touchIdEnabled;
/// Per-item refusal of a delete (the system restores the item).
+ (NSError *)deletionRejected;
+ (NSError *)noSuchItem;
+ (NSError *)syncAnchorExpired;
+ (NSError *)cannotSynchronize;
+ (NSError *)filenameCollision;
+ (NSError *)insufficientQuota;

/// Maps an error coming out of the Seafile SDK (AFNetworking / NSURLError)
/// to the closest NSFileProviderError. Errors already in the File Provider
/// domain are returned unchanged.
+ (NSError *)errorForSeafError:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
