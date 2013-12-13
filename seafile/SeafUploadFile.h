//
//  SeafUploadFile.h
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuickLook/QuickLook.h>

#import "Utils.h"

@class SeafConnection;
@class SeafUploadFile;
@class SeafDir;

@protocol SeafUploadDelegate <NSObject>
- (void)uploadProgress:(SeafUploadFile *)file result:(BOOL)res completeness:(int)percent;
- (void)uploadSucess:(SeafUploadFile *)file oid:(NSString *)oid;
@end


@interface SeafUploadFile : NSObject<PreViewDelegate, QLPreviewItem>

@property (readonly) NSString *lpath;
@property (readonly) NSString *name;
@property (readonly) long long filesize;

@property (readonly) BOOL uploading;
@property (readonly) int uProgress;
@property id<SeafUploadDelegate> delegate;

@property (readwrite) SeafDir *udir;

- (id)initWithPath:(NSString *)lpath;
- (void)upload:(SeafConnection *)connection repo:(NSString *)repoId path:(NSString *)uploadpath update:(BOOL)update;

- (void)removeFile;

- (BOOL)uploaded;

- (NSString *)key;
- (NSMutableDictionary *)uploadAttr;
- (void)saveAttr:(NSMutableDictionary *)attr;

+ (NSMutableArray *)uploadFilesForDir:(SeafDir *)dir;

@end
