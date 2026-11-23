//
//  SeafConnection+ResumableUpload.h
//  Seafile
//
//  Server calls used by resumable uploads (plan §5.4). Completions run on the
//  main queue, like the rest of SeafConnection. `status` is the HTTP status,
//  0 when no response arrived.
//

#import "SeafConnection.h"

NS_ASSUME_NONNULL_BEGIN

@interface SeafConnection (ResumableUpload)

/// Server >= 7.0, the master switch on, and the account not marked as unsupported/downgraded.
@property (nonatomic, readonly) BOOL isResumableUploadSupported;

- (nullable NSURLSessionDataTask *)resumable_uploadedBytesInRepo:(NSString *)repoId
                                                       parentDir:(NSString *)parentDir
                                                        fileName:(NSString *)fileName
                                                      lastModify:(nullable NSString *)lastModify
                                                      completion:(void (^)(NSInteger status, NSString * _Nullable acceptRanges,
                                                                           id _Nullable body, NSError * _Nullable error))completion;

- (nullable NSURLSessionDataTask *)resumable_uploadLinkInRepo:(NSString *)repoId
                                                    parentDir:(NSString *)parentDir
                                                   completion:(void (^)(NSString * _Nullable url, NSInteger status,
                                                                        NSError * _Nullable error))completion;

/// v2.1 file info: obj_name, obj_id, size, mtime. 404 when the file does not exist.
- (nullable NSURLSessionDataTask *)resumable_fileInfoInRepo:(NSString *)repoId
                                                       path:(NSString *)path
                                                 completion:(void (^)(NSInteger status, NSDictionary * _Nullable info,
                                                                      NSError * _Nullable error))completion;

/// Directory entries (dicts with name, id, type, size).
- (nullable NSURLSessionDataTask *)resumable_listDirInRepo:(NSString *)repoId
                                                      path:(NSString *)path
                                                completion:(void (^)(NSInteger status, NSArray<NSDictionary *> * _Nullable entries,
                                                                     NSError * _Nullable error))completion;

/// v2.1 rename; the server renames on a name clash and returns the result in obj_name.
- (nullable NSURLSessionDataTask *)resumable_renameFileInRepo:(NSString *)repoId
                                                         path:(NSString *)path
                                                      newName:(NSString *)newName
                                                   completion:(void (^)(NSInteger status, NSDictionary * _Nullable info,
                                                                        NSError * _Nullable error))completion;

- (void)resumable_deleteFileInRepo:(NSString *)repoId
                              path:(NSString *)path
                        completion:(void (^)(NSInteger status, NSError * _Nullable error))completion;

/// Reusable download link (plan §6.4 reads several ranges through it).
- (nullable NSURLSessionDataTask *)resumable_downloadURLInRepo:(NSString *)repoId
                                                          path:(NSString *)path
                                                    completion:(void (^)(NSString * _Nullable url, NSInteger status,
                                                                         NSError * _Nullable error))completion;

/// Range GET; `status` must be 206 for the data to be a range.
- (nullable NSURLSessionDownloadTask *)resumable_readRangeFromURL:(NSString *)url
                                                           offset:(long long)offset
                                                           length:(NSUInteger)length
                                                       completion:(void (^)(NSData * _Nullable data, NSInteger status,
                                                                            NSError * _Nullable error))completion;

/// One segment POST, body streamed from a file.
- (nullable NSURLSessionUploadTask *)resumable_uploadSegment:(NSURLRequest *)request
                                                    fromFile:(NSURL *)bodyFile
                                                    progress:(nullable void (^)(int64_t sent, int64_t total))progress
                                                  completion:(void (^)(NSHTTPURLResponse * _Nullable response, id _Nullable body,
                                                                       NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
