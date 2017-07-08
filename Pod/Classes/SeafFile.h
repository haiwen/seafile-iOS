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

typedef void (^SeafFileDidDownloadBlock)(SeafFile* _Nonnull file, BOOL result);


@protocol SeafFileUpdateDelegate <NSObject>
- (void)updateProgress:(nonnull SeafFile * )file progress:(int)percent;
- (void)updateComplete:(nonnull SeafFile * )file result:(BOOL)res;

@end

@interface SeafFile : SeafBase<QLPreviewItem, SeafPreView, SeafUploadDelegate, SeafDownloadDelegate> {
@protected
    long long _filesize;
    long long _mtime;
    NSString *_shareLink;

}

- (nonnull id)initWithConnection:(nonnull SeafConnection *)aConnection
                     oid:(nullable NSString *)anId
                  repoId:(nonnull NSString *)aRepoId
                    name:(nonnull NSString *)aName
                    path:(nonnull NSString *)aPath
                   mtime:(long long)mtime
                    size:(unsigned long long)size;

@property (strong, nonatomic, nullable) NSString *mpath;// For modified files
@property (readonly, nullable) NSString *detailText;
@property (readonly) long long filesize;
@property (readonly) long long mtime;
@property (strong, nullable) id <SeafFileUpdateDelegate> udelegate;
@property (strong, nonatomic) NSProgress * _Nullable progress;
@property (assign, nonatomic) NSTimeInterval failTime;
@property (copy, nonatomic) NSString * _Nullable userIdentifier;

- (BOOL)isStarred;
- (void)setStarred:(BOOL)starred;
- (void)deleteCache;
- (void)update:(nullable id<SeafFileUpdateDelegate>)dg;
- (void)cancelAnyLoading;
- (BOOL)itemChangedAtURL:(nonnull NSURL *)url;
- (nonnull NSDictionary *)toDict;

- (nullable NSString *)cachePath;

- (void)setThumbCompleteBlock:(nullable void (^)(BOOL ret))block;
- (void)setFileDownloadedBlock:(nullable SeafFileDidDownloadBlock)block;
- (void)downloadThumb:(nullable id<SeafDownloadDelegate>)downloadTask;

- (BOOL)waitUpload;


@end
