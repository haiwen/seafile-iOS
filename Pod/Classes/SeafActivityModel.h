//
//  SeafActivityModel.h
//  Seafile
//
//  Created by three on 2019/6/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafActivityModel : NSObject

@property (nonatomic, copy) NSString *authorName;

@property (nonatomic, copy) NSString *time;

@property (nonatomic, copy) NSString *operation;

@property (nonatomic, strong) NSURL *avatarURL;

@property (nonatomic, copy) NSString *repoName;

@property (nonatomic, copy) NSString *detail;

- (instancetype)initWithEventJSON:(NSDictionary *)event andOpsMap:(NSDictionary *)opsMap;

@end

NS_ASSUME_NONNULL_END
