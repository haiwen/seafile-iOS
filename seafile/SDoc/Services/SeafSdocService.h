//  SeafSdocService.h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SeafConnection;

@interface SeafFileProfileAggregate : NSObject
@property (nonatomic, strong, nullable) NSDictionary *fileDetail;
@property (nonatomic, strong, nullable) NSDictionary *metadataConfig;
@property (nonatomic, strong, nullable) NSDictionary *recordWrapper;
@property (nonatomic, strong, nullable) NSDictionary *relatedUsers;
@property (nonatomic, strong, nullable) NSDictionary *tagWrapper;
@end

@interface SeafSdocService : NSObject

// Designated initializer
- (instancetype)initWithConnection:(SeafConnection *)connection;

// GET methods
- (void)getFileDetailWithRepoId:(NSString *)repoId path:(NSString *)path completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;
- (void)getMetadataWithRepoId:(NSString *)repoId completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;
- (void)getRelatedUsersWithRepoId:(NSString *)repoId completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;
- (void)getRecordsWithRepoId:(NSString *)repoId parentDir:(NSString *)parentDir name:(NSString *)name fileName:(NSString *)fileName completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;
- (void)getTagsWithRepoId:(NSString *)repoId completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;

// Aggregate fetch (stage1: detail+metadata, stage2: records/users/tags based on config)
- (void)fetchFileProfileAggregateWithRepoId:(NSString *)repoId
                                       path:(NSString *)path
                                 completion:(void(^)(SeafFileProfileAggregate * _Nullable agg, NSError * _Nullable error))completion;

// PUT methods (JSON body, aligning Android SDocService)

/// Update metadata record fields (PUT /api/v2.1/repos/{repo_id}/metadata/record/)
/// @param data Dictionary of field name→value to update (pass nil to skip)
- (void)putRecordWithRepoId:(NSString *)repoId
                   recordId:(NSString *)recordId
                       data:(NSDictionary * _Nullable)data
                 completion:(void(^)(BOOL success, NSError * _Nullable error))completion;

/// Update file tags (PUT /api/v2.1/repos/{repo_id}/metadata/file-tags/)
/// @param tagIds Array of tag ID strings to set (pass nil to skip)
- (void)putRecordTagWithRepoId:(NSString *)repoId
                      recordId:(NSString *)recordId
                        tagIds:(NSArray<NSString *> * _Nullable)tagIds
                    completion:(void(^)(BOOL success, NSError * _Nullable error))completion;

/// Combined save: PUT record data + PUT tags in parallel (aligns Android SDocViewModel.putRecord)
/// Skips individual calls if data/tagIds is nil.
- (void)saveProfileWithRepoId:(NSString *)repoId
                     recordId:(NSString *)recordId
                         data:(NSDictionary * _Nullable)data
                       tagIds:(NSArray<NSString *> * _Nullable)tagIds
                   completion:(void(^)(BOOL success, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END


