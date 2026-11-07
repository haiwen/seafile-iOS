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

/// What a failed directory listing says about the directory: decides whether
/// a working set pass goes on to the next directory, and whether the parent
/// has to be listed to retire this one.
typedef NS_ENUM(NSInteger, SeafFPListingFailure) {
    SeafFPListingFailureNone = 0,
    SeafFPListingFailureMissing,     // Seahub's own 404: the folder (or library) is not there
    SeafFPListingFailureDirectory,   // about this directory only: 403, any other 4xx, its library locked or gone
    SeafFPListingFailureServer,      // unreachable, timed out, 5xx, 401, or a 404 that is not Seahub's
};

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
+ (NSError *)pageExpired;
+ (NSError *)cannotSynchronize;
+ (NSError *)filenameCollision;
+ (NSError *)insufficientQuota;

/// Maps an error coming out of the Seafile SDK (AFNetworking / NSURLError)
/// to the closest NSFileProviderError. Errors already in the File Provider
/// domain are returned unchanged.
+ (NSError *)errorForSeafError:(nullable NSError *)error;
/// A directory listing 404 is conclusive only with Seahub's missing-path error.
+ (NSError *)directoryListingErrorForSeafError:(nullable NSError *)error;
/// The same judgement for the working set checks. A proxy's or an HTML page's
/// 404 says nothing about the path and counts as the server not answering.
+ (SeafFPListingFailure)listingFailureForSeafError:(nullable NSError *)error;
/// YES when the server refused this one request (403, above quota, any other
/// 4xx): a later answer to something else does not say the refusal is over.
/// NO when the server or the session did not answer (unreachable, timed out,
/// 5xx, 401, 408 / 429), which the next fresh answer settles. Decides how
/// soon the error may be signalled as resolved (SeafFPErrorResolution).
+ (BOOL)seafErrorConcernsOneItem:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
