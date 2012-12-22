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

@protocol SeafUploadDelegate <NSObject>
- (void)uploadProgress:(SeafUploadFile *)file result:(BOOL)res completeness:(int)percent;
@end


@interface SeafUploadFile : NSObject<NSURLConnectionDelegate, PreViewDelegate, QLPreviewItem>


@property (readonly) NSString *path;

@property (readonly) NSString *name;
@property (readonly) int filesize;

@property (readonly) BOOL uploading;
@property (readonly) int uploadProgress;
@property id<SeafUploadDelegate> delegate;

- (id)initWithPath:(NSString *)path;
- (void)upload:(SeafConnection *)connection repo:(NSString *)repoId dir:(NSString *)dir;

- (void)removeFile;

@end
