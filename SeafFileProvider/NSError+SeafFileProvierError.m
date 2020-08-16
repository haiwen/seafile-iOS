//
//  NSError+SeafFileProvierError.m
//  SeafFileProvider
//
//  Created by three on 2018/6/13.
//  Copyright © 2018年 Seafile. All rights reserved.
//

#import "NSError+SeafFileProvierError.h"
#import <FileProvider/FileProvider.h>
#import "Utils.h"

@implementation NSError (SeafFileProvierError)

+ (NSError *)fileProvierErrorServerUnreachable {
    if (@available(iOS 11.0, *)) {
        return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorServerUnreachable userInfo:nil];
    } else {
        return [Utils defaultError];
    }
}

+ (NSError *)fileProvierErrorNotAuthenticated {
    if (@available(iOS 11.0, *)) {
        return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorNotAuthenticated userInfo:@{@"reason" : @"notAuthenticated"}];
    } else {
        return [Utils defaultError];
    }
}

+ (NSError *)fileProvierErrorNoAccount {
    if (@available(iOS 11.0, *)) {
        return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorNotAuthenticated userInfo:@{@"reason" : @"noAccount"}];
    } else {
        return [Utils defaultError];
    }
}

+ (NSError *)fileProvierErrorNoSuchItem {
    if (@available(iOS 11.0, *)) {
        return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorNoSuchItem userInfo:nil];
    } else {
        return [Utils defaultError];
    }
}

+ (NSError *)fileProvierErrorPageExpired {
    if (@available(iOS 11.0, *)) {
        return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorPageExpired userInfo:nil];
    } else {
        return [Utils defaultError];
    }
}

+ (NSError *)fileProvierErrorFilenameCollision {
    if (@available(iOS 11.0, *)) {
        return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorFilenameCollision userInfo:nil];
    } else {
        return [Utils defaultError];
    }
}

+ (NSError *)fileProvierErrorInsufficientQuota {
    if (@available(iOS 11.0, *)) {
        return [[NSError alloc] initWithDomain:NSFileProviderErrorDomain code:NSFileProviderErrorInsufficientQuota userInfo:nil];
    } else {
        return [Utils defaultError];
    }
}


@end
