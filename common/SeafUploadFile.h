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

@protocol SeafUploadDelegate <NSObject>
- (void)uploadProgress:(SeafUploadFile *)file result:(BOOL)res progress:(int)percent;
- (void)uploadSucess:(SeafUploadFile *)file oid:(NSString *)oid;
@end


@interface SeafUploadFile : NSObject<SeafPreView, QLPreviewItem>

@property (readonly) NSString *lpath;
@property (readonly) NSString *name;
@property (readonly) long long filesize;

@property (readonly) BOOL uploading;
@property (readwrite) BOOL update;
@property (nonatomic, readwrite) ALAsset *asset;
@property (readwrite, nonatomic) NSURL *assetURL;
@property (readwrite) BOOL autoSync;

@property (readonly) int uProgress;
@property id<SeafUploadDelegate> delegate;

@property (readwrite) SeafDir *udir;

- (id)initWithPath:(NSString *)lpath;
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

@end
