//
//  SeafCachePhoto.h
//  Seafile
//
//  Created by three on 2023/12/16.
//

#import "RLMObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface SeafCachePhoto : RLMObject

// account+assetIdentifier
@property (nonatomic, copy) NSString *identifier;
// true or false
@property (nonatomic, copy) NSString *status;
// host+username
@property (nonatomic, copy) NSString *account;

@end

NS_ASSUME_NONNULL_END
