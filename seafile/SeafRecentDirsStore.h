//
//  SeafRecentDirsStore.h
//  seafile
//

#import <Foundation/Foundation.h>
#import "SeafDir.h"

NS_ASSUME_NONNULL_BEGIN

@interface SeafRecentDirsStore : NSObject

+ (instancetype)shared;

// Save a directory as recently used for the given account (connection)
- (void)addRecentDirectory:(SeafDir *)directory;

// Read recent directories (newest first). Max defaults to 20 if max <= 0
- (NSArray<NSDictionary *> *)recentDirectoriesForConnection:(SeafConnection *)connection maxCount:(NSInteger)max;

// Helper to build a SeafDir instance from a stored dictionary
- (nullable SeafDir *)directoryFromRecord:(NSDictionary *)record connection:(SeafConnection *)connection;

@end

NS_ASSUME_NONNULL_END


