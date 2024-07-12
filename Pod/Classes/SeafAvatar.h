//
//  SeafAvatar.h
//  seafilePro
//
//  Created by Wang Wei on 4/11/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SeafConnection.h"
#import "SeafTaskQueue.h"
/**
 * @class SeafAvatar
 * @discussion This class handles the avatar functionality for Seafile, including downloading and caching avatars.
 */
@interface SeafAvatar : NSObject<SeafTask>

@property (nonatomic, readonly) NSString * accountIdentifier;
/**
 * Custom initializer for creating a SeafAvatar object.
 * @param aConnection A SeafConnection instance for network communication.
 * @param url The URL to download the avatar from.
 * @param path The file path to store the downloaded avatar.
 * @return An initialized SeafAvatar object.
 */
- (id)initWithConnection:(SeafConnection *)aConnection from:(NSString *)url toPath:(NSString *)path;

/**
 * Clears the cached avatar attributes by deleting the plist file.
 */
+ (void)clearCache;

@end

/**
 * @class SeafUserAvatar
 * @discussion Handles the user-specific avatar functionality by extending SeafAvatar.
 */
@interface SeafUserAvatar : SeafAvatar
- (id)initWithConnection:(SeafConnection *)aConnection username:(NSString *)username;

/**
 * Constructs the path for storing the user avatar.
 * @param conn The SeafConnection object.
 * @param username The username whose avatar is being processed.
 * @return A string representing the file path.
 */
+ (NSString *)pathForAvatar:(SeafConnection *)conn username:(NSString *)username;

@end

