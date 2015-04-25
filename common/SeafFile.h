//
//  SeafFile.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <QuickLook/QuickLook.h>
#import "SeafConnection.h"
#import "SeafUploadFile.h"
#import "SeafBase.h"
#import "Utils.h"


@class SeafFile;

@protocol SeafFileUpdateDelegate <NSObject>
- (void)updateProgress:(SeafFile *)file result:(BOOL)res completeness:(int)percent;
@end

@interface SeafFile : SeafBase<QLPreviewItem, SeafPreView, SeafUploadDelegate, SeafDownloadDelegate> {
@protected
    long long _filesize;
    long long _mtime;
    NSString *_shareLink;

}

- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    name:(NSString *)aName
                    path:(NSString *)aPath
                   mtime:(long long)mtime
                    size:(unsigned long long)size;

@property (strong, nonatomic) NSString *mpath;// For modified files
@property (readonly) NSString *detailText;
@property (readonly) long long filesize;
@property (readonly) long long mtime;
@property (strong) id <SeafFileUpdateDelegate> udelegate;

- (BOOL)isStarred;
- (void)setStarred:(BOOL)starred;
- (void)deleteCache;
- (void)update:(id<SeafFileUpdateDelegate>)dg;
- (void)cancelDownload;
- (BOOL)itemChangedAtURL:(NSURL *)url;
- (NSDictionary *)toDict;

@end
