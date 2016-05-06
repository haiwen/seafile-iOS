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
#define LARGE_FILE_SIZE 10*1024*1024

@class SeafConnection;
@class SeafUploadFile;
@class SeafDir;

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

@property (readonly) int uProgress;
@property (nonatomic) id<SeafUploadDelegate> delegate;

@property (readwrite) SeafDir *udir;

- (id)initWithPath:(NSString *)lpath;

- (void)setAsset:(ALAsset *)asset url:(NSURL *)url;
- (void)doUpload;

- (void)doRemove;
- (BOOL)canUpload;
- (BOOL)uploaded;

- (NSString *)key;
- (NSMutableDictionary *)uploadAttr;
- (BOOL)saveAttr:(NSMutableDictionary *)attr flush:(BOOL)flush;

+ (NSMutableArray *)uploadFilesForDir:(SeafDir *)dir;
+ (BOOL)saveAttrs;
+ (void)clearCache;

- (BOOL)waitUpload;


@end
