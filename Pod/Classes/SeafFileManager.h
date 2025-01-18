#import "SeafBase.h"
#import <Foundation/Foundation.h>
#import "SeafFileStateManager.h"
#import "SeafCacheManager.h"
#import "SeafFileModel.h"
#import "SeafConnection.h"

@interface SeafFileManager : NSObject

@property (nonatomic, weak) id<SeafFileDelegate> delegate;
@property (nonatomic, weak) SeafConnection *connection;
@property (nonatomic, strong) SeafCacheManager *cacheManager;
@property (nonatomic, strong) SeafFileStateManager *stateManager;

- (instancetype)initWithConnection:(SeafConnection *)connection;

// 下载相关方法
- (void)downloadFile:(SeafFileModel *)file 
           progress:(void(^)(float progress))progressBlock
         completion:(void(^)(BOOL success, NSError *error))completion;

- (void)cancelDownload:(SeafFileModel *)file;

// 上传相关方法
- (void)uploadFile:(SeafUploadFile *)file;
- (void)cancelUpload:(SeafUploadFile *)file;

// 缓存相关方法
- (BOOL)hasLocalCache:(SeafFileModel *)file;
- (void)clearCache:(SeafFileModel *)file;

@end
