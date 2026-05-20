//  SeafSdocService.m

#import "SeafSdocService.h"
#import "SeafConnection.h"
#import "ExtentedString.h"

@implementation SeafFileProfileAggregate
@end

@interface SeafSdocService ()
@property (nonatomic, weak) SeafConnection *connection;
@end

@implementation SeafSdocService

- (instancetype)initWithConnection:(SeafConnection *)connection
{
    if (self = [super init]) {
        _connection = connection;
    }
    return self;
}

- (void)getFileDetailWithRepoId:(NSString *)repoId path:(NSString *)path completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion
{
    NSString *url = [NSString stringWithFormat:@"/api2/repos/%@/file/detail/?p=%@", repoId, [path escapedUrl]];
    [self.connection sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        if (completion) completion(JSON, nil);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        if (completion) completion(nil, error);
    }];
}

- (void)getMetadataWithRepoId:(NSString *)repoId completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion
{
    NSString *url = [NSString stringWithFormat:@"/api/v2.1/repos/%@/metadata/", repoId];
    [self.connection sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        if (completion) completion(JSON, nil);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        if (completion) completion(nil, error);
    }];
}

- (void)getRelatedUsersWithRepoId:(NSString *)repoId completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion
{
    NSString *url = [NSString stringWithFormat:@"/api/v2.1/repos/%@/related-users/", repoId];
    [self.connection sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        if (completion) completion(JSON, nil);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        if (completion) completion(nil, error);
    }];
}

- (void)getRecordsWithRepoId:(NSString *)repoId parentDir:(NSString *)parentDir name:(NSString *)name fileName:(NSString *)fileName completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion
{
    if (parentDir.length == 0) parentDir = @"/";
    NSString *url = [NSString stringWithFormat:@"/api/v2.1/repos/%@/metadata/record/?parent_dir=%@&name=%@&file_name=%@",
                     repoId, [parentDir escapedUrl], [name escapedUrl], [fileName escapedUrl]];
    [self.connection sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        if (completion) completion(JSON, nil);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        if (completion) completion(nil, error);
    }];
}

- (void)getTagsWithRepoId:(NSString *)repoId completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion
{
    NSString *url = [NSString stringWithFormat:@"/api/v2.1/repos/%@/metadata/tags/?start=0&limit=1000", repoId];
    [self.connection sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        if (completion) completion(JSON, nil);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        if (completion) completion(nil, error);
    }];
}

- (void)fetchFileProfileAggregateWithRepoId:(NSString *)repoId
                                       path:(NSString *)path
                                 completion:(void(^)(SeafFileProfileAggregate * _Nullable agg, NSError * _Nullable error))completion
{
    dispatch_queue_t guardQueue = dispatch_queue_create("com.seafile.profileAggregate", DISPATCH_QUEUE_SERIAL);

    __block NSDictionary *detail = nil;
    __block NSDictionary *meta = @{};
    __block NSError *detailError = nil;

    dispatch_group_t g1 = dispatch_group_create();

    dispatch_group_enter(g1);
    [self getFileDetailWithRepoId:repoId path:path completion:^(NSDictionary * _Nullable resp, NSError * _Nullable error) {
        dispatch_async(guardQueue, ^{
            detail = resp;
            if (error) detailError = error;
            dispatch_group_leave(g1);
        });
    }];

    dispatch_group_enter(g1);
    [self getMetadataWithRepoId:repoId completion:^(NSDictionary * _Nullable resp, NSError * _Nullable error) {
        dispatch_async(guardQueue, ^{
            // Metadata is optional: continue with empty config when the endpoint fails.
            meta = error ? @{} : (resp ?: @{});
            dispatch_group_leave(g1);
        });
    }];

    dispatch_group_notify(g1, dispatch_get_main_queue(), ^{
        if (![detail isKindOfClass:[NSDictionary class]]) {
            if (completion) completion(nil, detailError);
            return;
        }

        SeafFileProfileAggregate *agg = [SeafFileProfileAggregate new];
        agg.fileDetail = detail;
        agg.metadataConfig = meta;

        BOOL metaEnabled = [meta[@"enabled"] boolValue];
        BOOL tagsEnabled = [meta[@"tags_enabled"] boolValue];

        if (!metaEnabled && !tagsEnabled) {
            if (completion) completion(agg, nil);
            return;
        }

        __block NSDictionary *record = nil;
        __block NSDictionary *users = nil;
        __block NSDictionary *tags = nil;
        __block NSError *stage2Error = nil;

        NSString *parentDir = @"/";
        NSString *name = path ?: @"";
        NSRange r = [path rangeOfString:@"/" options:NSBackwardsSearch];
        if (r.location != NSNotFound) {
            parentDir = [path substringToIndex:r.location];
            name = [path substringFromIndex:r.location+1];
            if (parentDir.length == 0) parentDir = @"/";
        }

        dispatch_group_t g2 = dispatch_group_create();

        if (metaEnabled) {
            dispatch_group_enter(g2);
            [self getRecordsWithRepoId:repoId parentDir:parentDir name:name fileName:name completion:^(NSDictionary * _Nullable resp, NSError * _Nullable error) {
                dispatch_async(guardQueue, ^{
                    record = resp;
                    if (error && !stage2Error) stage2Error = error;
                    dispatch_group_leave(g2);
                });
            }];

            dispatch_group_enter(g2);
            [self getRelatedUsersWithRepoId:repoId completion:^(NSDictionary * _Nullable resp, NSError * _Nullable error) {
                dispatch_async(guardQueue, ^{
                    users = resp;
                    if (error && !stage2Error) stage2Error = error;
                    dispatch_group_leave(g2);
                });
            }];
        }

        if (tagsEnabled) {
            dispatch_group_enter(g2);
            [self getTagsWithRepoId:repoId completion:^(NSDictionary * _Nullable resp, NSError * _Nullable error) {
                dispatch_async(guardQueue, ^{
                    tags = resp;
                    if (error && !stage2Error) stage2Error = error;
                    dispatch_group_leave(g2);
                });
            }];
        }

        dispatch_group_notify(g2, dispatch_get_main_queue(), ^{
            agg.recordWrapper = record;
            agg.relatedUsers = users;
            agg.tagWrapper = tags;
            if (completion) completion(agg, stage2Error);
        });
    });
}

@end
