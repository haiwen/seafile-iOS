//
//  SeafActivityModel.h
//  Seafile
//
//  Created by three on 2019/6/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafActivityModel : NSObject

@property (nonatomic, copy) NSString *author_name;

@property (nonatomic, copy) NSString *time;

@property (nonatomic, copy) NSString *operation;

@property (nonatomic, strong) NSURL *avatar_url;

@property (nonatomic, copy) NSString *repo_name;

@property (nonatomic, copy) NSString *detail;

- (instancetype)initWithNewAPIRequestJSON:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
