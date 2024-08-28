//
//  SeafStarredDir.h
//  Seafile
//
//  Created by henry on 2024/8/18.
//

#import "SeafDir.h"

NS_ASSUME_NONNULL_BEGIN

@interface SeafStarredDir : SeafDir

@property (nonatomic, assign) int isDir;//is file or dir
@property (nonatomic, assign) long long mtime;//modify time
@property (readonly, nullable) NSString *detailText;///< A string providing detailed information about the file.

- (id)initWithConnection:(SeafConnection *)aConnection Info:(NSDictionary *)infoDict;

@end

NS_ASSUME_NONNULL_END
