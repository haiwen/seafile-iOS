//
//  SeafChunkRequestBuilder.h
//  Seafile
//
//  Builds one segment request of a resumable upload (plan §5.2): the multipart
//  body is written to a file, copied from the source in 256 KiB pieces while
//  its SHA-1 is computed, so memory stays flat even in the extensions.
//  Also hosts the small file helpers the session needs (hashes, identity,
//  spot-check windows). Foundation only.
//

#import <Foundation/Foundation.h>
#import "SeafResumableUploadRecord.h"

NS_ASSUME_NONNULL_BEGIN

@interface SeafChunkRequest : NSObject
@property (nonatomic, readonly) NSMutableURLRequest *request;
@property (nonatomic, readonly) NSURL *bodyFileURL;
/// SHA-1 (hex) of the source bytes in this segment.
@property (nonatomic, readonly) NSString *segmentHash;
@property (nonatomic, readonly) long long start;
/// Inclusive.
@property (nonatomic, readonly) long long end;
@property (nonatomic, readonly) BOOL isLastChunk;
@end

@interface SeafChunkRequestBuilder : NSObject

+ (nullable SeafChunkRequest *)buildRequestForURL:(NSURL *)uploadURL
                                         filePath:(NSString *)filePath
                                            start:(long long)start
                                              end:(long long)end
                                         fileSize:(long long)fileSize
                                      stagingName:(NSString *)stagingName
                                        parentDir:(NSString *)parentDir
                                       lastModify:(nullable NSString *)lastModify
                                      isLastChunk:(BOOL)isLastChunk
                                  outputDirectory:(NSString *)outputDirectory
                                            error:(NSError **)error;

+ (void)removeBodyFile:(nullable SeafChunkRequest *)request;

/// SHA-1 (hex) of `length` bytes from `start`; nil if the file is shorter or unreadable.
+ (nullable NSString *)sha1OfFileAtPath:(NSString *)path start:(long long)start length:(long long)length;

/// "device:inode:size:mtime" of a local file, nil if it does not exist.
+ (nullable NSString *)fileIdentityAtPath:(NSString *)path;

/// One window per segment: the first `windowLength` bytes that contain a non-zero
/// byte. Segments that are entirely zero are skipped (a hole would read the same).
+ (nullable NSArray<SeafProbeWindow *> *)probeWindowsForFileAtPath:(NSString *)path
                                                          fileSize:(long long)fileSize
                                                         chunkSize:(long long)chunkSize
                                                      windowLength:(NSUInteger)windowLength
                                                             error:(NSError **)error;

/// Percent-encodes everything except A-Z a-z 0-9 - _ . ~ (the server decodes with QueryUnescape).
+ (NSString *)encodedFilename:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
