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

@interface NSObject (NSObjectValue)
- (long long)integerValue:(int)defaultValue;
- (BOOL)booleanValue:(BOOL)defaultValue;
- (NSString *)stringValue;

@end

enum SEAFBASE_STATE {
    SEAF_DENTRY_INIT = 0,
    SEAF_DENTRY_LOADING,
    SEAF_DENTRY_UPTODATE,
    SEAF_DENTRY_SUCCESS,
    SEAF_DENTRY_FAILURE,
};

@class SeafBase;

typedef void (^repo_password_set_block_t)(SeafBase *entry, int ret);


@protocol SeafShareDelegate <NSObject>
- (void)generateSharelink:(SeafBase *)entry WithResult:(BOOL)success;
@end

@interface SeafBase : NSObject<SeafItem>
{
@public
    SeafConnection *connection;
}
- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    name:(NSString *)aName
                    path:(NSString *)aPath
                    mime:(NSString *)aMime;


@property (copy) NSString *name; // name
@property (readonly, copy) NSString *path; // path in the library
@property (readonly, copy) NSString *repoId; // library id
@property (readonly, copy) NSString *mime; //mime type
@property (nonatomic, copy) NSString *dirPath; // full path

@property (copy) NSString *ooid; // cached object id
@property (copy) NSString *oid;  // current object id

@property enum SEAFBASE_STATE state; // the state of local object

@property (weak) id <SeafDentryDelegate> delegate; // the delegate

@property (readonly, copy) NSString *shareLink; // shared link

- (BOOL)hasCache;  // has local cache
- (BOOL)loadCache; // load local cache
- (void)clearCache;  // clear local cache

// load the content of this entry, force means force load from server. Otherwise will try to load local cache first, if cache miss, load from remote server.
- (void)loadContent:(BOOL)force;
- (UIImage *)icon; // icon for this entry

- (void)generateShareLink:(id<SeafShareDelegate>)dg; // generate shared link


// The following functions are used internally.
- (NSString *)key; // The key used to sort
- (NSString *)cacheKey; //the key used for cache
- (void)updateWithEntry:(SeafBase *)entry;

- (void)downloadComplete:(BOOL)updated;
- (void)downloadFailed:(NSError *)error;
- (void)generateShareLink:(id<SeafShareDelegate>)dg type:(NSString *)type;

@end
