//  SeafDocsCommentService.m

#import "SeafDocsCommentService.h"
#import "SeafGlobal.h"
#import "Version.h"
#import "SeafConnection.h"
#import "SeadocImageUploadOperation.h"
#import "SeafDataTaskManager.h"

@interface SeafDocsCommentService ()
@property (nonatomic, weak) SeafConnection *connection;
@end

@implementation SeafDocsCommentService

static NSString * const kSeafDocsCommentServiceErrorDomain = @"SeafDocsCommentService";

- (NSString *)normalizeBase:(NSString *)server
{
    if (server.length == 0) return @"";
    NSString *base = server;
    if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length-1];
    return base;
}

- (NSMutableURLRequest *)jsonRequestWithServer:(NSString *)server
                                          path:(NSString *)path
                                        method:(NSString *)method
                                          token:(NSString *)token
                                           body:(NSData * _Nullable)body
{
    NSString *base = [self normalizeBase:server];
    NSString *urlStr = [NSString stringWithFormat:@"%@%@", base, path ?: @""];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return nil;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method ?: @"GET";
    if (body) req.HTTPBody = body;
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if ([method.uppercaseString isEqualToString:@"POST"] || [method.uppercaseString isEqualToString:@"PUT"]) {
        if (![[req valueForHTTPHeaderField:@"Content-Type"] length]) {
            [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        }
    }
    if (token.length > 0) {
        [req setValue:[NSString stringWithFormat:@"Token %@", token] forHTTPHeaderField:@"Authorization"];
        [req setValue:SEAFILE_VERSION forHTTPHeaderField:@"X-Seafile-Client-Version"];
    }
    return req;
}

// Decide if we should retry once on network/5xx
- (BOOL)shouldRetryForResponse:(NSHTTPURLResponse *)http error:(NSError *)error
{
    if (error) return YES;
    NSInteger code = http.statusCode;
    return (code >= 500 && code <= 599);
}

- (void)sendJSONRequest:(NSMutableURLRequest *)req
                attempt:(NSInteger)attempt
             completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion
{
    if (!req) {
        if (completion) completion(nil, [NSError errorWithDomain:kSeafDocsCommentServiceErrorDomain code:-2 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"bad url", nil)}]);
        return;
    }
    __weak typeof(self) wself = self;
    [self.connection sendPreparedRequest:req
                                 success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id  _Nonnull JSON) {
        if (![JSON isKindOfClass:NSDictionary.class]) {
            if (completion) completion(nil, [NSError errorWithDomain:kSeafDocsCommentServiceErrorDomain code:-4 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"unexpected payload", nil)}]);
            return;
        }
        if (completion) completion((NSDictionary *)JSON, nil);
    } failure:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id  _Nullable JSON, NSError * _Nullable error) {
        __strong typeof(wself) sself = wself; if (!sself) { if (completion) completion(nil, error); return; }
        if ([sself shouldRetryForResponse:response error:error] && attempt == 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [sself sendJSONRequest:req attempt:1 completion:completion];
            });
            return;
        }
        if (completion) completion(nil, error);
    }];
}

- (instancetype)init
{
    return [self initWithConnection:nil];
}

- (instancetype)initWithConnection:(SeafConnection * _Nullable)connection
{
    self = [super init];
    if (self) {
        _connection = connection ?: [SeafGlobal sharedObject].connection;
    }
    return self;
}

- (void)getElementsWithDocUUID:(NSString *)uuid seadocServer:(NSString *)server token:(NSString *)token completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion
{
    if (uuid.length == 0 || server.length == 0) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:kSeafDocsCommentServiceErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"invalid params", nil)}]); });
        return;
    }
    NSString *path = [NSString stringWithFormat:@"/api/v1/docs/%@/", uuid];
    NSMutableURLRequest *req = [self jsonRequestWithServer:server path:path method:@"GET" token:token body:nil];
    [self sendJSONRequest:req attempt:0 completion:completion];
}

- (void)getCommentsWithDocUUID:(NSString *)uuid seadocServer:(NSString *)server token:(NSString *)token completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion
{
    if (uuid.length == 0 || server.length == 0) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:kSeafDocsCommentServiceErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"invalid params", nil)}]); });
        return;
    }
    NSString *path = [NSString stringWithFormat:@"/api/v1/docs/%@/comment/", uuid];
    NSMutableURLRequest *req = [self jsonRequestWithServer:server path:path method:@"GET" token:token body:nil];
    [self sendJSONRequest:req attempt:0 completion:completion];
}

- (void)postCommentForDocUUID:(NSString *)uuid
                 seadocServer:(NSString *)server
                        token:(NSString *)token
                      comment:(NSString *)comment
                       author:(NSString *)author
                    updatedAt:(NSString *)updatedAt
                   completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion
{
    if (uuid.length == 0 || server.length == 0 || comment.length == 0) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:kSeafDocsCommentServiceErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"invalid params", nil)}]); });
        return;
    }

    NSDictionary *detail = @{ @"element_id": @"0", @"comment": comment };
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"comment"] = comment ?: @"";
    params[@"detail"] = detail;
    // Ensure required fields (align Android): author uses current account email first, fallback to username
    NSString *finalAuthor = author;
    if (finalAuthor.length == 0) {
        SeafConnection *conn = [SeafGlobal sharedObject].connection;
        finalAuthor = conn.email ?: @"";
        if (finalAuthor.length == 0) {
            finalAuthor = conn.username ?: @"";
        }
        if (finalAuthor.length == 0) {
            finalAuthor = @"unknown";
        }
    }
    NSString *finalUpdatedAt = updatedAt;
    if (finalUpdatedAt.length == 0) {
        if (@available(iOS 10.0, *)) {
            NSISO8601DateFormatter *fmt = [NSISO8601DateFormatter new];
            finalUpdatedAt = [fmt stringFromDate:[NSDate date]];
        } else {
            NSDateFormatter *df = [NSDateFormatter new];
            df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            df.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
            finalUpdatedAt = [df stringFromDate:[NSDate date]];
        }
    }
    params[@"author"] = finalAuthor;
    params[@"updated_at"] = finalUpdatedAt;

    NSData *body = [NSJSONSerialization dataWithJSONObject:params options:0 error:nil];
    NSString *path = [NSString stringWithFormat:@"/api/v1/docs/%@/comment/", uuid];
    NSMutableURLRequest *req = [self jsonRequestWithServer:server path:path method:@"POST" token:token body:body];
    [self sendJSONRequest:req attempt:0 completion:completion];
}

- (void)markResolvedForDocUUID:(NSString *)uuid
                    commentId:(long long)commentId
                  seadocServer:(NSString *)server
                         token:(NSString *)token
                    completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion
{
    if (uuid.length == 0 || server.length == 0 || commentId <= 0) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:kSeafDocsCommentServiceErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"invalid params", nil)}]); });
        return;
    }
    NSDictionary *payload = @{ @"resolved": @YES };
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *path = [NSString stringWithFormat:@"/api/v1/docs/%@/comment/%lld/", uuid, commentId];
    NSMutableURLRequest *req = [self jsonRequestWithServer:server path:path method:@"PUT" token:token body:body];
    [self sendJSONRequest:req attempt:0 completion:completion];
}

- (void)deleteCommentForDocUUID:(NSString *)uuid
                       commentId:(long long)commentId
                     seadocServer:(NSString *)server
                            token:(NSString *)token
                       completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion
{
    if (uuid.length == 0 || server.length == 0 || commentId <= 0) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:kSeafDocsCommentServiceErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"invalid params", nil)}]); });
        return;
    }
    NSString *path = [NSString stringWithFormat:@"/api/v1/docs/%@/comment/%lld/", uuid, commentId];
    NSMutableURLRequest *req = [self jsonRequestWithServer:server path:path method:@"DELETE" token:token body:nil];
    [self sendJSONRequest:req attempt:0 completion:completion];
}

-(void)uploadImageForDocUUID:(NSString *)uuid
                seadocServer:(NSString *)server
                       token:(NSString *)token
                     fileData:(NSData *)fileData
                      mimeType:(NSString *)mime
                      fileName:(NSString *)fileName
                    completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion
{
    if (uuid.length == 0 || server.length == 0 || fileData.length == 0 || mime.length == 0 || fileName.length == 0) {
        if (completion) completion(nil, [NSError errorWithDomain:@"SeafDocsCommentService" code:-1 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"invalid params", nil)}]);
        return;
    }
    SeafConnection *conn = self.connection ?: [SeafGlobal sharedObject].connection;
    if (!conn) { if (completion) completion(nil, [NSError errorWithDomain:@"SeafDocsCommentService" code:-5 userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"no connection", nil)}]); return; }

    __weak typeof(self) wself = self;
    SeadocImageUploadOperation *op = [[SeadocImageUploadOperation alloc] initWithConnection:conn
                                                                                     docUUID:uuid
                                                                              seadocServerUrl:server
                                                                          seadocAccessToken:token
                                                                                    fileData:fileData
                                                                                     fileName:fileName
                                                                                     mimeType:mime
                                                                                   completion:^(NSArray<NSString *> * _Nullable relativePaths, NSError * _Nullable error) {
        __strong typeof(wself) sself = wself; (void)sself;
        if (completion) {
            if (error) { completion(nil, error); }
            else { completion(@{ @"relative_path": relativePaths ?: @[] }, nil); }
        }
    }];

    SeafAccountTaskQueue *q = [SeafDataTaskManager.sharedObject accountQueueForConnection:conn];
    [q addCommentImageUploadOperation:op];
}

@end

