//
//  SeafResumableUploadDefines.m
//  Seafile
//

#import "SeafResumableUploadDefines.h"

BOOL const SeafResumableUploadEnabled = YES;

long long const SeafResumableChunkSize = 8LL * 1024 * 1024;
long long const SeafResumableMinFileSize = 10LL * 1024 * 1024;

NSString * const SeafResumableStagingPrefix = @".seafile-upload-";

NSString * const SeafResumableErrorDomain = @"SeafResumableUpload";

NSString * const SeafResumableEntryShare = @"share";
