//
//  SeafChunkRequestBuilder.m
//  Seafile
//

#import "SeafChunkRequestBuilder.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>

static const NSUInteger kCopyBufferSize = 256 * 1024;
static const NSTimeInterval kSegmentTimeout = 60;
static const NSTimeInterval kFinalSegmentTimeout = 600;

@interface SeafChunkRequest ()
@property (nonatomic, readwrite) NSMutableURLRequest *request;
@property (nonatomic, readwrite) NSURL *bodyFileURL;
@property (nonatomic, readwrite) NSString *segmentHash;
@property (nonatomic, readwrite) long long start;
@property (nonatomic, readwrite) long long end;
@property (nonatomic, readwrite) BOOL isLastChunk;
@end
@implementation SeafChunkRequest
@end

static NSString *HexDigest(unsigned char *digest, NSUInteger length)
{
    NSMutableString *hex = [NSMutableString stringWithCapacity:length * 2];
    for (NSUInteger i = 0; i < length; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static NSError *BuilderError(NSString *message)
{
    return [NSError errorWithDomain:@"SeafChunkRequestBuilder" code:-1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation SeafChunkRequestBuilder

+ (NSString *)encodedFilename:(NSString *)name
{
    static NSCharacterSet *allowed;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
                   @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"];
    });
    return [name stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

+ (NSURL *)URLWithRetJSON:(NSURL *)url
{
    NSString *s = url.absoluteString;
    if ([s containsString:@"ret-json="]) return url;
    NSString *joined = [s stringByAppendingString:([s containsString:@"?"] ? @"&ret-json=1" : @"?ret-json=1")];
    return [NSURL URLWithString:joined] ?: url;
}

+ (NSData *)fieldWithBoundary:(NSString *)boundary name:(NSString *)name value:(NSString *)value
{
    NSString *s = [NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",
                   boundary, name, value];
    return [s dataUsingEncoding:NSUTF8StringEncoding];
}

+ (SeafChunkRequest *)buildRequestForURL:(NSURL *)uploadURL
                                filePath:(NSString *)filePath
                                   start:(long long)start
                                     end:(long long)end
                                fileSize:(long long)fileSize
                             stagingName:(NSString *)stagingName
                               parentDir:(NSString *)parentDir
                              lastModify:(NSString *)lastModify
                             isLastChunk:(BOOL)isLastChunk
                         outputDirectory:(NSString *)outputDirectory
                                   error:(NSError **)error
{
    if (start < 0 || end < start || end >= fileSize) {
        if (error) *error = BuilderError(@"Invalid segment range");
        return nil;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:outputDirectory withIntermediateDirectories:YES attributes:nil error:error]) return nil;

    NSFileHandle *source = [NSFileHandle fileHandleForReadingAtPath:filePath];
    if (!source) {
        if (error) *error = BuilderError(@"Cannot open the source file");
        return nil;
    }
    NSString *bodyPath = [outputDirectory stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"body"]];
    if (![fm createFileAtPath:bodyPath contents:nil attributes:nil]) {
        [source closeFile];
        if (error) *error = BuilderError(@"Cannot create the request body file");
        return nil;
    }
    NSFileHandle *body = [NSFileHandle fileHandleForWritingAtPath:bodyPath];
    NSString *boundary = [NSString stringWithFormat:@"Boundary+%@", [NSUUID UUID].UUIDString];
    NSString *encodedName = [self encodedFilename:stagingName];

    BOOL ok = YES;
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    @try {
        [body writeData:[self fieldWithBoundary:boundary name:@"parent_dir" value:parentDir]];
        if (lastModify.length > 0) {
            [body writeData:[self fieldWithBoundary:boundary name:@"last_modify" value:lastModify]];
            [body writeData:[self fieldWithBoundary:boundary name:@"file_mtime" value:lastModify]];
        }
        // The part's own filename is the staging name too: if a proxy strips
        // both headers, the server falls back to it (plan §5.2).
        NSString *fileHeader = [NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\n"
                                "Content-Type: application/octet-stream\r\n\r\n", boundary, stagingName];
        [body writeData:[fileHeader dataUsingEncoding:NSUTF8StringEncoding]];

        CC_SHA1_CTX ctx;
        CC_SHA1_Init(&ctx);
        [source seekToFileOffset:(unsigned long long)start];
        long long remaining = end - start + 1;
        while (remaining > 0) {
            @autoreleasepool {
                NSData *piece = [source readDataOfLength:(NSUInteger)MIN((long long)kCopyBufferSize, remaining)];
                if (piece.length == 0) { ok = NO; break; }
                CC_SHA1_Update(&ctx, piece.bytes, (CC_LONG)piece.length);
                [body writeData:piece];
                remaining -= (long long)piece.length;
            }
        }
        CC_SHA1_Final(digest, &ctx);
        [body writeData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    } @catch (NSException *e) {
        ok = NO;
    }
    [source closeFile];
    [body closeFile];
    if (!ok) {
        [fm removeItemAtPath:bodyPath error:nil];
        if (error) *error = BuilderError(@"The source file is shorter than expected");
        return nil;
    }

    unsigned long long length = [[fm attributesOfItemAtPath:bodyPath error:nil] fileSize];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self URLWithRetJSON:uploadURL]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = isLastChunk ? kFinalSegmentTimeout : kSegmentTimeout;
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"%llu", length] forHTTPHeaderField:@"Content-Length"];
    [request setValue:[NSString stringWithFormat:@"attachment; filename=\"%@\"", encodedName] forHTTPHeaderField:@"Content-Disposition"];
    [request setValue:[NSString stringWithFormat:@"bytes %lld-%lld/%lld", start, end, fileSize] forHTTPHeaderField:@"Content-Range"];

    SeafChunkRequest *result = [SeafChunkRequest new];
    result.request = request;
    result.bodyFileURL = [NSURL fileURLWithPath:bodyPath];
    result.segmentHash = HexDigest(digest, CC_SHA1_DIGEST_LENGTH);
    result.start = start;
    result.end = end;
    result.isLastChunk = isLastChunk;
    return result;
}

+ (void)removeBodyFile:(SeafChunkRequest *)request
{
    if (request.bodyFileURL) [[NSFileManager defaultManager] removeItemAtURL:request.bodyFileURL error:nil];
}

+ (NSString *)sha1OfFileAtPath:(NSString *)path start:(long long)start length:(long long)length
{
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh || start < 0 || length < 0) return nil;
    CC_SHA1_CTX ctx;
    CC_SHA1_Init(&ctx);
    BOOL ok = YES;
    @try {
        [fh seekToFileOffset:(unsigned long long)start];
        long long remaining = length;
        while (remaining > 0) {
            @autoreleasepool {
                NSData *piece = [fh readDataOfLength:(NSUInteger)MIN((long long)kCopyBufferSize, remaining)];
                if (piece.length == 0) { ok = NO; break; }
                CC_SHA1_Update(&ctx, piece.bytes, (CC_LONG)piece.length);
                remaining -= (long long)piece.length;
            }
        }
    } @catch (NSException *e) {
        ok = NO;
    }
    [fh closeFile];
    if (!ok) return nil;
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &ctx);
    return HexDigest(digest, CC_SHA1_DIGEST_LENGTH);
}

+ (NSString *)fileIdentityAtPath:(NSString *)path
{
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) != 0) return nil;
    return [NSString stringWithFormat:@"%lld:%llu:%lld:%ld.%09ld", (long long)st.st_dev, (unsigned long long)st.st_ino,
            (long long)st.st_size, (long)st.st_mtimespec.tv_sec, (long)st.st_mtimespec.tv_nsec];
}

+ (NSArray<SeafProbeWindow *> *)probeWindowsForFileAtPath:(NSString *)path
                                                 fileSize:(long long)fileSize
                                                chunkSize:(long long)chunkSize
                                             windowLength:(NSUInteger)windowLength
                                                    error:(NSError **)error
{
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) {
        if (error) *error = BuilderError(@"Cannot open the source file");
        return nil;
    }
    NSMutableArray *windows = [NSMutableArray array];
    BOOL ok = YES;
    @try {
        for (long long segStart = 0; segStart < fileSize; segStart += chunkSize) {
            long long segEnd = MIN(segStart + chunkSize, fileSize);
            long long pos = segStart;
            [fh seekToFileOffset:(unsigned long long)segStart];
            BOOL found = NO;
            while (pos < segEnd && !found) {
                @autoreleasepool {
                    NSData *piece = [fh readDataOfLength:(NSUInteger)MIN((long long)kCopyBufferSize, segEnd - pos)];
                    if (piece.length == 0) { ok = NO; break; }
                    const uint8_t *bytes = piece.bytes;
                    for (NSUInteger i = 0; i < piece.length; i++) {
                        if (bytes[i] == 0) continue;
                        // Window starts at the first non-zero byte, clamped to stay inside the segment.
                        long long winStart = MIN(pos + (long long)i, MAX(segStart, segEnd - (long long)windowLength));
                        NSUInteger len = (NSUInteger)MIN((long long)windowLength, segEnd - winStart);
                        [fh seekToFileOffset:(unsigned long long)winStart];
                        NSData *window = [fh readDataOfLength:len];
                        if (window.length != len) { ok = NO; break; }
                        unsigned char digest[CC_SHA1_DIGEST_LENGTH];
                        CC_SHA1(window.bytes, (CC_LONG)window.length, digest);
                        [windows addObject:[SeafProbeWindow windowWithOffset:winStart length:len
                                                                        sha1:HexDigest(digest, CC_SHA1_DIGEST_LENGTH)]];
                        found = YES;
                        break;
                    }
                    pos += (long long)piece.length;
                }
            }
            if (!ok) break;
        }
    } @catch (NSException *e) {
        ok = NO;
    }
    [fh closeFile];
    if (!ok) {
        if (error) *error = BuilderError(@"Cannot read the source file");
        return nil;
    }
    return windows;
}

@end
