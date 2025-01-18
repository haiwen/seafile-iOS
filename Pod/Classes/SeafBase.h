//
//  SeafBase.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafConnection.h"
#import "Debug.h"

// Download callback related states
typedef enum {
    SEAF_DENTRY_INIT = 0,
    SEAF_DENTRY_LOADING,
    SEAF_DENTRY_SUCCESS,
    SEAF_DENTRY_FAILURE,
    SEAF_DENTRY_UPTODATE,
} SeafDentryState;

@interface NSObject (NSObjectValue)
- (long long)integerValue:(int)defaultValue;
- (BOOL)booleanValue:(BOOL)defaultValue;
- (NSString *_Nullable)stringValue;

@end

@class SeafBase;
@class SeafConnection;
@protocol SeafDentryDelegate <NSObject>
- (void)download:(id _Nullable)entry complete:(BOOL)updated;
- (void)download:(id _Nullable)entry failed:(NSError *_Nullable)error;
- (void)download:(id _Nonnull )entry progress:(float)progress;
@end

@protocol SeafShareDelegate <NSObject>
- (void)generateSharelink:(SeafBase *)entry WithResult:(BOOL)success;
@end

@interface SeafBase : NSObject

@property (nonatomic, weak, nullable) id<SeafDentryDelegate> delegate;    // Delegate object
@property (nonatomic, assign) SeafDentryState state;                      // Download or loading state

/**
 * Points to SeafConnection, used for network requests and repository management.
 * Note: Injected during init, use strong or weak reference based on actual needs.
 */
@property (nonatomic, weak, nullable) SeafConnection *connection;

/**
 * Unique identifier, used to distinguish different SeafBase instances 
 * (combining account, repoId, path and other information).
 * If a special uniqueKey needs to be generated in subclasses, 
 * the getter of this property can be overridden.
 */
@property (nonatomic, copy, nullable) NSString *uniqueKey;

/**
 * Whether it's an encrypted repository.
 * Used when determining if the repository is encrypted or needs a password
 * (called by subclass or upper layer).
 */
@property (nonatomic, assign) BOOL encrypted;

/**
 * Whether cache file exists (implementation depends on business logic).
 */
@property (nonatomic, assign, readonly) BOOL hasCache;

/**
 Load (or update) the data/content of this entry. 
 Subclasses should determine whether to force fetch based on the force parameter.
 @param force Whether to force refresh (ignore local cache and fetch directly from server)
 */
- (void)loadContent:(BOOL)force;

/**
 Clear cache
 */
- (void)clearCache;

/**
 Set starred (favorite)
 */
- (void)setStarred:(BOOL)starred;

/**
 Check if password is required (encrypted repository)
 */
- (BOOL)passwordRequiredWithSyncRefresh;

/**
 Set repository password
 */
- (void)setRepoPassword:(NSString * _Nullable)password block:(void(^_Nullable)(SeafBase * _Nullable entry, int ret))block;

/**
 Get/generate share link
 */
- (void)generateShareLink:(id<SeafShareDelegate>_Nonnull)dg;
- (void)generateShareLink:(id<SeafShareDelegate>_Nonnull)dg
                 password:(nullable NSString *)password
              expire_days:(nullable NSString *)expire_days;

- (instancetype _Nullable)initWithConnection:(SeafConnection * _Nullable)aConnection
                               oid:(nullable NSString *)anId
                            repoId:(nullable NSString *)aRepoId
                              name:(nullable NSString *)aName
                              path:(nullable NSString *)aPath
                              mime:(nullable NSString *)aMime;

- (BOOL)loadCache; // load local cache
- (NSString * _Nullable)cacheKey; //the key used for cache
- (NSString * _Nullable)key; // The key used to sort
- (void)updateWithEntry:(SeafBase * _Nullable)entry;
- (UIImage * _Nullable)icon; // icon for this entry
@property (readonly, copy) NSString * _Nullable mime; //mime type
@property (readonly, copy) NSString * _Nullable shareLink; // shared link
@property (readonly, copy) NSString * _Nullable repoId; // library id
@property (readonly, copy) NSString * _Nullable path; // path in the library
@property (copy) NSString *_Nullable oid;  // current object id
@property (copy) NSString *_Nullable ooid; // cached object id
typedef void (^repo_password_set_block_t)(SeafBase * _Nullable entry, int ret);
@property (nonatomic, copy) NSString * _Nullable repoName;//repo name
@property (nonatomic, assign) BOOL isDeleted;//2.9.27 mark is deleted
@property (copy) NSString * _Nullable name; //obj name
@property (nonatomic, copy) NSString * _Nullable fullPath; // full path

@end
