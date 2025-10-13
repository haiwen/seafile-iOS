//  SeafSdocService.h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SeafConnection;
@class SeafFileProfileAggregate;

@interface SeafSdocService : NSObject

// Designated initializer
- (instancetype)initWithConnection:(SeafConnection *)connection;

// Placeholder methods to align with Android services; implement as needed later
- (void)getFileDetailWithRepoId:(NSString *)repoId path:(NSString *)path completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;
- (void)getMetadataWithRepoId:(NSString *)repoId completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;
- (void)getRelatedUsersWithRepoId:(NSString *)repoId completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;
- (void)getRecordsWithRepoId:(NSString *)repoId parentDir:(NSString *)parentDir name:(NSString *)name fileName:(NSString *)fileName completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;
- (void)getTagsWithRepoId:(NSString *)repoId completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;

// Aggregate fetch (stage1: detail+metadata, stage2: records/users/tags based on config)
- (void)fetchFileProfileAggregateWithRepoId:(NSString *)repoId
                                       path:(NSString *)path
                                 completion:(void(^)(SeafFileProfileAggregate * _Nullable agg, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

