//
//  NSError+SeafFileProvierError.m
//  SeafFileProvider
//
//  Created by three on 2018/6/13.
//  Copyright © 2018年 Seafile. All rights reserved.
//

#import "NSError+SeafFileProvierError.h"
#import <FileProvider/FileProvider.h>

@implementation NSError (SeafFileProvierError)

+ (NSError *)fileProvierErrorServerUnreachable {
    return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorServerUnreachable userInfo:nil];
}

+ (NSError *)fileProvierErrorNotAuthenticated {
    return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorNotAuthenticated userInfo:@{@"reason" : @"notAuthenticated"}];
}

+ (NSError *)fileProvierErrorNoAccount {
    return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorNotAuthenticated userInfo:@{@"reason" : @"noAccount"}];
}

+ (NSError *)fileProvierErrorNoSuchItem {
    return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorNoSuchItem userInfo:nil];
}

+ (NSError *)fileProvierErrorPageExpired {
    return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorPageExpired userInfo:nil];
}

+ (NSError *)fileProvierErrorSyncAnchorExpired {
    return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorSyncAnchorExpired userInfo:nil];
}

+ (NSError *)fileProvierErrorFilenameCollision {
    return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorFilenameCollision userInfo:nil];
}

+ (NSError *)fileProvierErrorInsufficientQuota {
    return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorInsufficientQuota userInfo:nil];
}

+ (NSError *)fileProvierErrorFeatureUnsupported {
    return [NSError errorWithDomain:NSCocoaErrorDomain code:NSFeatureUnsupportedError userInfo:@{}];
}


@end
