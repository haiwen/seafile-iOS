//
//  SeafGlobal.h
//  seafilePro
//
//  Created by Wang Wei on 11/9/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//


#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "SeafConnection.h"
#import "SeafDbCacheProvider.h"
#import "SeafPreView.h"

@protocol SeafBackgroundMonitor <NSObject>
- (void)enterBackground;
- (void)enterForeground;
@end


@interface SeafGlobal : NSObject<SeafBackgroundMonitor>

@property (readonly) NSMutableArray *conns;
@property (readwrite) SeafConnection *connection;
@property (readonly) dispatch_semaphore_t saveAlbumSem;
@property (readonly) SeafDbCacheProvider *cacheProvider;

@property (readonly) NSArray *publicAccounts;

+ (SeafGlobal *)sharedObject;

- (BOOL)isCertInUse:(NSData*)clientIdentityKey;
- (void)loadAccounts;
/// Re-reads the persisted account list, rebuilding the connections when it has changed.
/// Returns YES in that case, so callers can drop whatever they cached against the old
/// accounts. Cheap when nothing changed.
- (BOOL)syncAccountsFromStorage;
- (SeafConnection *)getConnection:(NSString *)url username:(NSString *)username;
- (BOOL)saveConnection:(SeafConnection *)conn;
- (BOOL)removeConnection:(SeafConnection *)conn;

- (void)notifyFileProviderRootChanged;
- (void)startTimer;
- (void)migrate;

@end

