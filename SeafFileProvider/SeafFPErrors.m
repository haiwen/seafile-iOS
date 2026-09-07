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

// Same key AFNetworking uses; spelled out so this file does not import AFNetworking.
static NSString * const kAFFailingResponseKey = @"com.alamofire.serialization.response.error.response";

@implementation SeafFPErrors

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

+ (NSError *)errorForSeafError:(NSError *)error
{
    if (!error) {
        return [self serverUnreachable];
    }
    if ([error.domain isEqualToString:NSFileProviderErrorDomain]) {
        return error;
    }
    NSInteger status = 0;
    id response = error.userInfo[kAFFailingResponseKey];
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        status = ((NSHTTPURLResponse *)response).statusCode;
    }
    switch (status) {
        case 401:
        case 403:
            return [self notAuthenticated];
        case 404:
            return [self noSuchItem];
        case 409:
        case 443: // Seafile: name already exists
            return [self filenameCollision];
        case 507:
            return [self insufficientQuota];
        default:
            break;
    }
    if (status >= 400 && status < 500) {
        return [self cannotSynchronize];
    }
    return [self serverUnreachable];
}

@end
