//
//  SeafAvatar.h
//  seafilePro
//
//  Created by Wang Wei on 4/11/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

//#import <Foundation/Foundation.h>
//#import "SeafConnection.h"
//#import "SeafTaskQueue.h"
///**
// * @class SeafAvatar
// * @discussion This class handles the avatar functionality for Seafile, including downloading and caching avatars.
// */
//@interface SeafAvatar : NSObject<SeafTask>
//
//@property (nonatomic, readonly) NSString * accountIdentifier;
///**
// * Custom initializer for creating a SeafAvatar object.
// * @param aConnection A SeafConnection instance for network communication.
// * @param url The URL to download the avatar from.
// * @param path The file path to store the downloaded avatar.
// * @return An initialized SeafAvatar object.
// */
//- (id)initWithConnection:(SeafConnection *)aConnection from:(NSString *)url toPath:(NSString *)path;
//
///**
// * Clears the cached avatar attributes by deleting the plist file.
// */
//+ (void)clearCache;
//
//@end
//

// SeafAvatar.h

#import <Foundation/Foundation.h>

@class SeafConnection;

/**
 * @class SeafAvatar
 * @discussion Represents a user's avatar in Seafile.
 */
@interface SeafAvatar : NSObject

@property (nonatomic, strong, readonly) SeafConnection *connection; ///< The connection associated with the avatar.
@property (nonatomic, copy, readonly) NSString *avatarPath; ///< The local file path where the avatar is stored.
@property (nonatomic, copy, readonly) NSString *email; ///< The email associated with the user's avatar.
@property (nonatomic, copy) NSString *avatarUrl;///< The URL from which to download the avatar.
@property (nonatomic, copy) NSString *path;///< The local file system path where the avatar is stored.
@property (nonatomic, assign) BOOL retryable;


- (instancetype)initWithConnection:(SeafConnection *)aConnection email:(NSString *)email;

/**
 * Returns YES if the avatar file exists locally.
 */
- (BOOL)hasAvatar;

/**
 * Called when the avatar download is complete.
 * @param success Indicates if the download was successful.
 */
- (void)downloadComplete:(BOOL)success;

/**
 * Clears the cached avatar attributes by deleting the plist file.
 */
+ (void)clearCache;

- (BOOL)modified:(long long)timestamp;

+ (NSMutableDictionary *)avatarAttrs;

- (void)saveAttrs:(NSMutableDictionary *)dict;

+ (void)saveAvatarAttrs;

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

