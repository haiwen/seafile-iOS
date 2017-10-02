//
//  SeafUploadFile.h
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuickLook/QuickLook.h>
#import <AssetsLibrary/AssetsLibrary.h>

#import "SeafPreView.h"

@class SeafConnection;
@class SeafUploadFile;
@class SeafDir;

typedef void (^SeafUploadProgressBlock)(SeafUploadFile *file, int progress);
typedef void (^SeafUploadCompletionBlock)(BOOL success, SeafUploadFile *file, NSString *oid);

@protocol SeafUploadDelegate <NSObject>
- (void)uploadProgress:(SeafUploadFile *)file progress:(int)percent;
- (void)uploadComplete:(BOOL)success file:(SeafUploadFile *)file oid:(NSString *)oid;
@end


@interface SeafUploadFile : NSObject<SeafPreView, QLPreviewItem>

@property (readonly) NSString *lpath;
@property (readonly) NSString *name;
@property (readonly) long long filesize;

@property (readonly) BOOL uploading;
@property (readwrite) BOOL overwrite;
@property (nonatomic, readonly) ALAsset *asset;
@property (nonatomic, readonly) NSURL *assetURL;
@property (readwrite) BOOL autoSync;
@property (readonly) BOOL removed;
@property (copy, nonatomic) NSString *userIdentifier;

@property (readonly) int uProgress;
@property (nonatomic) id<SeafUploadDelegate> delegate;
@property (nonatomic) SeafUploadProgressBlock progressBlock;
@property (nonatomic) SeafUploadCompletionBlock completionBlock;

@property (readwrite) SeafDir *udir;

- (id)initWithPath:(NSString *)lpath;

- (void)setAsset:(ALAsset *)asset url:(NSURL *)url;
- (void)doUpload;

- (void)cancel;
- (void)doRemove;
- (BOOL)canUpload;
- (BOOL)uploaded;

- (NSString *)key;
- (NSMutableDictionary *)uploadAttr;
- (BOOL)clearUploadAttr:(BOOL)flush;
- (BOOL)saveUploadAttr:(BOOL)flush;

+ (NSMutableArray *)uploadFilesForDir:(SeafDir *)dir;
+ (BOOL)saveAttrs;
+ (void)clearCache;

- (void)resetFailedAttempt;
- (BOOL)waitUpload;


@end
