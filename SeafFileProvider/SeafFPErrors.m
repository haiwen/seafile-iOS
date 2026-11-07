//
//  SeafFPErrors.m
//  SeafFileProvider
//

#import "SeafFPErrors.h"
#import <FileProvider/FileProvider.h>

NSString * const SeafFPErrorReasonKey = @"reason";
NSString * const SeafFPErrorReasonNotAuthenticated = @"notAuthenticated";
NSString * const SeafFPErrorReasonNoAccount = @"noAccount";
NSString * const SeafFPErrorReasonTouchIdEnabled = @"touchIdEnabled";

// Same keys AFNetworking uses; spelled out so this file does not import AFNetworking.
static NSString * const kAFFailingResponseKey = @"com.alamofire.serialization.response.error.response";
static NSString * const kAFFailingResponseDataKey = @"com.alamofire.serialization.response.error.data";

@implementation SeafFPErrors

/// The `error_msg` of a seahub error body, when the failure carried one.
+ (NSString *)seafErrorMessage:(NSError *)error
{
    NSData *data = error.userInfo[kAFFailingResponseDataKey];
    if (![data isKindOfClass:[NSData class]] || data.length == 0 || data.length > 4096) return nil;
    id body = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSString *message = [body isKindOfClass:[NSDictionary class]] ? body[@"error_msg"] : nil;
    return [message isKindOfClass:[NSString class]] && message.length > 0 ? message : nil;
}

+ (NSError *)errorWithCode:(NSFileProviderErrorCode)code userInfo:(NSDictionary *)userInfo
{
    return [NSError errorWithDomain:NSFileProviderErrorDomain code:code userInfo:userInfo];
}

+ (NSError *)serverUnreachable
{
    return [self errorWithCode:NSFileProviderErrorServerUnreachable userInfo:nil];
}

+ (NSError *)notAuthenticated
{
    return [self errorWithCode:NSFileProviderErrorNotAuthenticated
                      userInfo:@{SeafFPErrorReasonKey: SeafFPErrorReasonNotAuthenticated}];
}

+ (NSError *)noAccount
{
    return [self errorWithCode:NSFileProviderErrorNotAuthenticated
                      userInfo:@{SeafFPErrorReasonKey: SeafFPErrorReasonNoAccount}];
}

+ (NSError *)touchIdEnabled
{
    return [self errorWithCode:NSFileProviderErrorNotAuthenticated
                      userInfo:@{SeafFPErrorReasonKey: SeafFPErrorReasonTouchIdEnabled}];
}

+ (NSError *)deletionRejected
{
    return [self errorWithCode:NSFileProviderErrorDeletionRejected userInfo:nil];
}

+ (NSError *)noSuchItem
{
    return [self errorWithCode:NSFileProviderErrorNoSuchItem userInfo:nil];
}

+ (NSError *)syncAnchorExpired
{
    return [self errorWithCode:NSFileProviderErrorSyncAnchorExpired userInfo:nil];
}

+ (NSError *)pageExpired
{
    return [self errorWithCode:NSFileProviderErrorPageExpired userInfo:nil];
}

+ (NSError *)cannotSynchronize
{
    return [self errorWithCode:NSFileProviderErrorCannotSynchronize userInfo:nil];
}

+ (NSError *)filenameCollision
{
    return [self errorWithCode:NSFileProviderErrorFilenameCollision userInfo:nil];
}

+ (NSError *)insufficientQuota
{
    return [self errorWithCode:NSFileProviderErrorInsufficientQuota userInfo:nil];
}

/// The HTTP status a failure carries, 0 when the server never answered.
/// The file server refuses an upload in plain text ("Out of quota."), not
/// JSON. AFNetworking's JSON serializer then reports its own parse failure
/// and keeps the error that holds the response one level down, as the
/// underlying error. Only the quota statuses are read from there: a plain
/// text 403 of the file server (an expired upload link, a read-only folder)
/// would otherwise start to ask for a sign-in.
+ (NSInteger)statusOfSeafError:(NSError *)error
{
    id response = error.userInfo[kAFFailingResponseKey];
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        return ((NSHTTPURLResponse *)response).statusCode;
    }
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if (![underlying isKindOfClass:[NSError class]]) return 0;
    response = underlying.userInfo[kAFFailingResponseKey];
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) return 0;
    NSInteger status = ((NSHTTPURLResponse *)response).statusCode;
    return status == 443 || status == 507 ? status : 0;
}

+ (NSError *)errorForSeafError:(NSError *)error
{
    if (!error) {
        return [self serverUnreachable];
    }
    if ([error.domain isEqualToString:NSFileProviderErrorDomain]) {
        return error;
    }
    NSInteger status = [self statusOfSeafError:error];
    switch (status) {
        case 401:
        case 403:
            return [self notAuthenticated];
        case 404:
            return [self noSuchItem];
        case 409:
            return [self filenameCollision];
        case 443: // seahub HTTP_443_ABOVE_QUOTA / fileserver "Out of quota."
        case 507:
            return [self insufficientQuota];
        case 520: { // seahub HTTP_520_OPERATION_FAILED; "Above quota" when it is
            NSString *message = [self seafErrorMessage:error];
            if (message && [message rangeOfString:@"quota" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                return [self insufficientQuota];
            }
            return [self cannotSynchronize];
        }
        default:
            break;
    }
    if (status >= 400 && status < 500) {
        return [self cannotSynchronize];
    }
    return [self serverUnreachable];
}

/// Seahub's "Folder … not found." / "Library … not found.": the only 404 that
/// says the path is gone.
+ (BOOL)isSeahubMissingPathError:(NSError *)error
{
    NSString *message = [self seafErrorMessage:error];
    return ([message hasPrefix:@"Folder "] || [message hasPrefix:@"Library "]) && [message hasSuffix:@" not found."];
}

+ (NSError *)directoryListingErrorForSeafError:(NSError *)error
{
    NSError *mapped = [self errorForSeafError:error];
    if (mapped.code != NSFileProviderErrorNoSuchItem) return mapped;
    if (![self isSeahubMissingPathError:error]) {
        return [self serverUnreachable];
    }
    // The missing directory is not necessarily the item being modified.
    return [self errorWithCode:NSFileProviderErrorCannotSynchronize userInfo:@{SeafFPErrorReasonKey: @"directoryMissing"}];
}

+ (SeafFPListingFailure)listingFailureForSeafError:(NSError *)error
{
    NSInteger status = 0;
    id response = error.userInfo[kAFFailingResponseKey];
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        status = ((NSHTTPURLResponse *)response).statusCode;
    }
    if (status == 404) {
        return [self isSeahubMissingPathError:error] ? SeafFPListingFailureMissing : SeafFPListingFailureServer;
    }
    // 401 is the session, 408 / 429 the server asking for a pause: every
    // other listing fails the same way.
    if (status == 401 || status == 408 || status == 429) return SeafFPListingFailureServer;
    if (status >= 400 && status < 500) return SeafFPListingFailureDirectory;
    return SeafFPListingFailureServer;
}

+ (BOOL)seafErrorConcernsOneItem:(NSError *)error
{
    NSInteger status = [self statusOfSeafError:error];
    if (status == 0) return NO;   // never answered
    // 401 is the session, 408 / 429 the server asking for a pause.
    if (status == 401 || status == 408 || status == 429) return NO;
    // 507 and seahub's 520 "operation failed" are how quota and rejected
    // operations are reported outside the 4xx range (errorForSeafError:).
    if (status == 507 || status == 520) return YES;
    return status >= 400 && status < 500;
}

@end
