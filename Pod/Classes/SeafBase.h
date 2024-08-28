//
//  SeafDentry.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SeafPreView.h"

@class SeafConnection;

/**
 * An extension to NSObject to provide default value handling for different types.
 */
@interface NSObject (NSObjectValue)
- (long long)integerValue:(int)defaultValue;
- (BOOL)booleanValue:(BOOL)defaultValue;
- (NSString *)stringValue;

@end

/**
 * Enumeration that defines various states of a SeafBase entry.
 */
enum SEAFBASE_STATE {
    SEAF_DENTRY_INIT = 0,
    SEAF_DENTRY_LOADING,
    SEAF_DENTRY_UPTODATE,
    SEAF_DENTRY_SUCCESS,
    SEAF_DENTRY_FAILURE,
};

@class SeafBase;
/**
 * A block type for setting repository passwords.
 * @param entry The SeafBase object concerned.
 * @param ret The result of the password setting operation.
 */
typedef void (^repo_password_set_block_t)(SeafBase *entry, int ret);

/**
 * Protocol defining the delegate methods for sharing operations.
 */
@protocol SeafShareDelegate <NSObject>
- (void)generateSharelink:(SeafBase *)entry WithResult:(BOOL)success;
@end

/**
 * @class SeafBase
 * @discussion This class is the base class for Seafile entries, providing basic functionalities such as caching, sharing, and content management.
 */
@interface SeafBase : NSObject
{
@public
    SeafConnection *connection;///< Connection used for network operations related to this entry.
}
- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    name:(NSString *)aName
                    path:(NSString *)aPath
                    mime:(NSString *)aMime;


@property (copy) NSString *name; //obj name
@property (nonatomic, copy) NSString *repoName;//repo name
@property (readonly, copy) NSString *path; // path in the library
@property (readonly, copy) NSString *repoId; // library id
@property (readonly, copy) NSString *mime; //mime type
@property (nonatomic, copy) NSString *fullPath; // full path
@property (readonly, copy) NSString *uniqueKey; // unique key

@property (copy) NSString *ooid; // cached object id
@property (copy) NSString *oid;  // current object id

@property enum SEAFBASE_STATE state; // the state of local object

@property (weak) id <SeafDentryDelegate> delegate; // the delegate

@property (readonly, copy) NSString *shareLink; // shared link

@property (nonatomic, assign) BOOL isDeleted;//2.9.27 mark is deleted

@property (assign, nonatomic) BOOL encrypted;///< Indicates whether the repository is encrypted.

- (BOOL)hasCache;  // has local cache
- (BOOL)loadCache; // load local cache
- (void)clearCache;  // clear local cache

// load the content of this entry, force means force load from server. Otherwise will try to load local cache first, if cache miss, load from remote server.
- (void)loadContent:(BOOL)force;
- (UIImage *)icon; // icon for this entry

//starred page load content
- (void)loadStarredContent:(BOOL)force;

- (void)generateShareLink:(id<SeafShareDelegate>)dg; // generate shared link


// The following functions are used internally.
- (NSString *)key; // The key used to sort
- (NSString *)cacheKey; //the key used for cache
- (void)updateWithEntry:(SeafBase *)entry;

- (void)downloadComplete:(BOOL)updated;
- (void)downloadFailed:(NSError *)error;

/**
 * Sets the starred status of the file.
 * @param starred YES to star the file, NO to unstar.
 */
- (void)setStarred:(BOOL)starred;
@end
