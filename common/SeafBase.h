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
};

@class SeafBase;

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


@property (copy) NSString *name;
@property (readonly, copy) NSString *path;
@property (readonly, copy) NSString *repoId;
@property (readonly, copy) NSString *mime;

@property (copy) NSString *ooid;
@property (copy) NSString *oid;

@property int state;

@property (weak) id <SeafDentryDelegate> delegate;

@property (readonly, copy) NSString *shareLink;

- (BOOL)hasCache;
- (BOOL)loadCache;
- (void)clearCache;

- (void)loadContent:(BOOL)force;
- (void)updateWithEntry:(SeafBase *)entry;

- (void)setRepoPassword:(NSString *)password;
- (void)checkRepoPassword:(NSString *)password;

- (NSString *)key;
- (UIImage *)icon;

- (void)generateShareLink:(id<SeafShareDelegate>)dg type:(NSString *)type;

- (void)generateShareLink:(id<SeafShareDelegate>)dg;

@end
