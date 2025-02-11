//
//  SeafFileModel.h
//  Seafile
//
//  Created by henry on 2025/1/22.
//

#import "SeafBaseModel.h"
#import "SeafConnection.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SeafFileDelegate <NSObject>
- (void)download:(id)file complete:(BOOL)updated;
- (void)download:(id)file failed:(NSError *)error;
- (void)download:(id)file progress:(float)progress;
@end

@interface SeafFileModel : SeafBaseModel

/// File modification time
@property (nonatomic, assign) long long mtime;
/// File size
@property (nonatomic, assign) unsigned long long filesize;
/// Local cache path of the file
@property (nonatomic, copy, nullable) NSString *localPath;
/// Corresponding SeafConnection
@property (nonatomic, strong, nullable) SeafConnection *conn;

@property (nonatomic) BOOL retryable;

@property (nonatomic) NSInteger retryCount;

/**
 Custom initializer

 @param oid    Object ID
 @param repoId Repository ID
 @param name   File name
 @param path   File path in the repository
 @param mtime  File modification time
 @param size   File size
 @param conn   Corresponding SeafConnection
 */
- (instancetype)initWithOid:(NSString *)oid
                     repoId:(NSString *)repoId
                       name:(NSString *)name
                       path:(NSString *)path
                      mtime:(long long)mtime
                       size:(unsigned long long)size
                 connection:(nullable SeafConnection *)conn NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/** Generate a unique key to distinguish files with the same account, repository, and path */
- (NSString *)uniqueKey;

/** Determine if the file is an image */
- (BOOL)isImageFile;

/** Determine if the file is a video */
- (BOOL)isVideoFile;

/** Determine if the file is editable */
- (BOOL)isEditable;

/** Convert to dictionary, useful for serialization, logging, or other scenarios */
- (NSDictionary *)toDictionary;

@end

NS_ASSUME_NONNULL_END
