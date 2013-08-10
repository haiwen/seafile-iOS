//
//  SeafDentry.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SeafConnection;

@interface NSObject (NSObjectValue)
- (long long)integerValue:(int)defaultValue;
- (BOOL)booleanValue:(BOOL)defaultValue;
@end

enum SEAFBASE_STATE {
    SEAF_DENTRY_INIT = 0,
    SEAF_DENTRY_LOADING,
    SEAF_DENTRY_UPTODATE,
};

@class SeafBase;

@protocol SeafDentryDelegate <NSObject>
- (void)entry:(SeafBase *)entry contentUpdated:(BOOL)updated completeness:(int)percent;
- (void)entryContentLoadingFailed:(int)errCode entry:(SeafBase *)entry;
- (void)repoPasswordSet:(SeafBase *)entry WithResult:(BOOL)success;
- (void)entryChanged:(SeafBase *)entry;

@end

@interface SeafBase : NSObject
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


@property (copy) NSString *name;
@property (readonly, copy) NSString *path;
@property (readonly, copy) NSString *repoId;
@property (readonly, copy) NSString *mime;

@property (copy) NSString *ooid;
@property (copy) NSString *oid;

@property int state;

@property (weak) id <SeafDentryDelegate> delegate;

- (BOOL)loadCache;
- (void)loadContent:(BOOL)force;
- (void)updateWithEntry:(SeafBase *)entry;

- (void)checkRepoPassword:(NSString *)password;

- (NSString *)key;
- (UIImage *)image;
- (BOOL)hasCache;

@end
