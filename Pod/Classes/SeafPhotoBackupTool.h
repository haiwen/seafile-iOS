//
//  SeafPhotoBackupTool.h
//  Seafile
//
//  Created by three on 2024/1/25.
//

#import <Foundation/Foundation.h>

@class SeafConnection;
@class SeafDir;

@protocol SeafPhotoSyncWatcherDelegate <NSObject>
- (void)photoSyncChanged:(long)remain;
@end

@interface SeafPhotoBackupTool : NSObject

@property (nonatomic, strong) SeafConnection * _Nonnull connection;

@property (nonatomic, strong) SeafDir * _Nullable syncDir;

@property (weak) id<SeafPhotoSyncWatcherDelegate> _Nullable photSyncWatcher;

@property (nonatomic, strong) NSMutableArray * _Nullable photosArray;

@property (nonatomic, strong) NSMutableArray * _Nullable uploadingArray;

@property (nonatomic, assign) BOOL inAutoSync;

@property (nonatomic, assign) BOOL inCheckPhotoss;

- (instancetype _Nonnull )initWithConnection:(SeafConnection * _Nonnull)connection andLocalUploadDir:(NSString * _Nonnull)localUploadDir;

- (void)checkPhotos:(BOOL)force;

- (void)prepareForBackup;

- (void)resetAll;

- (NSUInteger)photosInSyncing;

- (void)resetUploadedPhotos;

- (void)clearUploadingVideos;

- (NSUInteger)photosInUploadingArray;

@end
