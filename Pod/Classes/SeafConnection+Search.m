//
//  SeafConnection+Search.m
//  seafile
//
//  Search-related helpers for distinguishing Pro/Community servers
//  and choosing the appropriate search API.
//

#import "SeafConnection+Search.h"
#import "SeafRepos.h"
#import "SeafDir.h"
#import "SeafFile.h"
#import "ExtentedString.h"

@interface SeafConnection (SearchPrivate)

- (NSDictionary *)serverInfo;

@end

@implementation SeafConnection (Search)

- (BOOL)isProServer
{
    NSDictionary *info = [self serverInfo];
    if (!info) return NO;
    NSArray *features = info[@"features"];
    return [features isKindOfClass:[NSArray class]] && [features containsObject:@"seafile-pro"];
}

- (BOOL)isCommunityServer
{
    NSDictionary *info = [self serverInfo];
    if (!info) return NO;
    return ![self isProServer];
}

- (BOOL)isAdvancedSearchEnabled
{
    NSDictionary *info = [self serverInfo];
    if (!info) return NO;
    NSArray *features = info[@"features"];
    if (![features isKindOfClass:[NSArray class]]) return NO;
    return [features containsObject:@"seafile-pro"] && [features containsObject:@"file-search"];
}

- (void)searchFileInRepo:(NSString *)repoId
                 keyword:(NSString *)keyword
                 success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSMutableArray *results))success
                 failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error))failure
{
    NSParameterAssert(repoId);
    NSParameterAssert(keyword);

    NSString *url = [NSString stringWithFormat:API_URL_V21"/search-file/?repo_id=%@&q=%@", repoId, [keyword escapedUrl]];

    [self sendRequest:url success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        NSMutableArray *results = [[NSMutableArray alloc] init];
        NSArray *items = [JSON isKindOfClass:[NSDictionary class]] ? [JSON objectForKey:@"data"] : nil;
        if (![items isKindOfClass:[NSArray class]]) {
            if (success) success(request, response, JSON, results);
            return;
        }

        for (NSDictionary *itemInfo in items) {
            if (![itemInfo isKindOfClass:[NSDictionary class]])
                continue;

            NSString *path = [itemInfo objectForKey:@"path"];
            if (![path isKindOfClass:[NSString class]] || path.length == 0)
                continue;

            NSString *type = [itemInfo objectForKey:@"type"];
            NSString *name = [path lastPathComponent];
            long long mtime = 0;
            id mtimeValue = [itemInfo objectForKey:@"mtime"];
            if ([mtimeValue respondsToSelector:@selector(longLongValue)]) {
                mtime = [mtimeValue longLongValue];
            }

            if ([type isKindOfClass:[NSString class]] && [type isEqualToString:@"folder"]) {
                SeafDir *dir = [[SeafDir alloc] initWithConnection:self oid:nil repoId:repoId perm:nil name:name path:path mtime:mtime];
                [results addObject:dir];
            } else {
                long long size = 0;
                id sizeValue = [itemInfo objectForKey:@"size"];
                if ([sizeValue respondsToSelector:@selector(longLongValue)]) {
                    size = [sizeValue longLongValue];
                }
                SeafFile *file = [[SeafFile alloc] initWithConnection:self oid:nil repoId:repoId name:name path:path mtime:mtime size:size];
                [results addObject:file];
            }
        }

        if (success) success(request, response, JSON, results);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
        if (failure) failure(request, response, JSON, error);
    }];
}

@end

