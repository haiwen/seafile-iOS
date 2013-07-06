//
//  SeafFile.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <QuickLook/QuickLook.h>
#import "SeafUploadFile.h"
#import "SeafBase.h"
#import "Utils.h"


@class SeafFile;

@protocol SeafFileDelegate <NSObject>
- (void)generateSharelink:(SeafFile *)entry WithResult:(BOOL)success;
@end

@protocol SeafFileUpdateDelegate <NSObject>
- (void)updateProgress:(SeafFile *)file result:(BOOL)res completeness:(int)percent;
@end

@interface SeafFile : SeafBase<QLPreviewItem, PreViewDelegate, NSURLConnectionDelegate, SeafUploadDelegate>

- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    name:(NSString *)aName
                    path:(NSString *)aPath
                   mtime:(int)mtime
                    size:(int)size;

@property (strong) NSString *mpath;// For modified files
@property (readonly) NSString *detailText;
@property (readwrite) int filesize;
@property (readwrite) int mtime;
@property (readonly, copy) NSString *shareLink;

- (void)generateShareLink:(id<SeafFileDelegate>)dg;

- (BOOL)isStarred;
- (void)setStarred:(BOOL)starred;
- (void)deleteCache;
- (void)update:(id<SeafFileUpdateDelegate>)dg;
- (void)cancelDownload;

@end
