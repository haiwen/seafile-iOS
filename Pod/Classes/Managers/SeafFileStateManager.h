//
//  SeafFileStateManager.h
//  AFNetworking
//
//  Created by henry on 2025/1/23.
//

#import "SeafFileStateManager.h"
#import "SeafFileStatus.h"
#import "SeafFileModel.h"
#import <QuickLook/QuickLook.h>
#import "SeafConnection.h"

@interface SeafFileStateManager : NSObject

- (instancetype)initWithConnection:(SeafConnection *)connection;

// 文件状态管理
- (void)updateFileStatus:(SeafFileModel *)file
                   state:(SeafFileStatus *)state
             localPath:(NSString *)localPath;

- (SeafFileStatus *)getFileStatus:(SeafFileModel *)file;
- (void)clearFileStatus:(SeafFileModel *)file;

// 文件状态查询
- (BOOL)isFileDownloaded:(SeafFileModel *)file;
- (BOOL)isFileDownloading:(SeafFileModel *)file;
- (BOOL)isFileUploading:(SeafFileModel *)file;
- (BOOL)hasLocalChanges:(SeafFileModel *)file;

@end

