//
//  SeafFileStatus.m
//  Seafile
//
//  Created by henry on 2024/12/31.
//

#import "SeafFileStatus.h"

@implementation SeafFileStatus

// Ensures that each record is uniquely identified by its "file path + email".
+ (NSString *)primaryKey {
    return @"uniquePath";
}

// Initialize with default values
- (instancetype)init {
    self = [super init];
    if (self) {
        _serverOID = @"";           // Default server OID
        _serverMTime = 0.0;         // Default server modification time
        _localMTime = 0.0;          // Default local modification time
        _localFilePath = @"";       // Default local file path
        _fileSize = 0.0;            // Default file size
        _accountIdentifier = @"";          // Default account identifier
        _uniquePath = @"";          // Default unique path
    }
    return self;
}

@end

// Enable Realm to work with this class
RLM_COLLECTION_TYPE(SeafFileStatus)
