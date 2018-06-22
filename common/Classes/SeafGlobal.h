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


#define SEAFILE_SUITE_NAME @"group.com.seafile.seafilePro"
#define APP_ID @"com.seafile.seafilePro"
#define SEAF_FILE_PROVIDER @"com.seafile.seafilePro.fileprovider"

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
- (SeafConnection *)getConnection:(NSString *)url username:(NSString *)username;
- (BOOL)saveConnection:(SeafConnection *)conn;
- (BOOL)removeConnection:(SeafConnection *)conn;

- (void)startTimer;
- (void)migrate;

@end

