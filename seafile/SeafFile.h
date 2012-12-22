//
//  SeafFile.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <QuickLook/QuickLook.h>

#import "SeafBase.h"
#import "Utils.h"


@class SeafFile;

@protocol SeafFileDelegate <NSObject>
- (void)generateSharelink:(SeafFile *)entry WithResult:(BOOL)success;
@end

@interface SeafFile : SeafBase<QLPreviewItem, PreViewDelegate, NSURLConnectionDelegate>

- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    name:(NSString *)aName
                    path:(NSString *)aPath
                   mtime:(int)mtime
                    size:(int)size;


@property (readonly) int filesize;
@property (readonly) int mtime;
@property (readonly) NSString *shareLink;

- (void)generateShareLink:(id<SeafFileDelegate>)dg;

- (BOOL)isStarred;
- (void)setStarred:(BOOL)starred;

@end
