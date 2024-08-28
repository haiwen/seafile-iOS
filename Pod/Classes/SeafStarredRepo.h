//
//  SeafStarredRepo.h
//  Seafile
//
//  Created by henry on 2024/8/16.
//

#import "SeafRepos.h"

NS_ASSUME_NONNULL_BEGIN

@interface SeafStarredRepo : SeafRepo

@property (nonatomic, assign) int isDir;//is file or dir

- (id)initWithConnection:(SeafConnection *)aConnection Info:(NSDictionary *)infoDict;

@end

NS_ASSUME_NONNULL_END
