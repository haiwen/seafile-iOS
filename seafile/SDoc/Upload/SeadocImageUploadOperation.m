//
//  SeadocImageUploadOperation.m
//

#import "SeadocImageUploadOperation.h"
#import "SeafConnection.h"
#import "Version.h"

@interface SeadocImageUploadOperation ()
@property (nonatomic, weak) SeafConnection *connection;
@property (nonatomic, copy) NSString *docUUID;
@property (nonatomic, copy) NSString *seadocServerUrl;
@property (nonatomic, copy) NSString *seadocAccessToken;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, strong) NSData *fileData;
@property (nonatomic, copy) SeadocImageUploadCompletion completion;

@property (nonatomic, strong) NSArray<NSString *> *relativePaths;
@property (nonatomic, strong) NSError *error;

@property (nonatomic, assign) NSInteger attempt;
@end

@implementation SeadocImageUploadOperation

- (instancetype)initWithConnection:(SeafConnection *)connection
                           docUUID:(NSString *)docUUID
                    seadocServerUrl:(NSString *)seadocServerUrl
                seadocAccessToken:(NSString *)seadocAccessToken
                          fileData:(NSData *)fileData
                           fileName:(NSString *)fileName
                           mimeType:(NSString *)mimeType
                         completion:(SeadocImageUploadCompletion)completion
{
    if (self = [super init]) {
        _connection = connection;
        _docUUID = [docUUID copy];
        _seadocServerUrl = [seadocServerUrl copy];
        _seadocAccessToken = [seadocAccessToken copy];
        _fileData = fileData;
        _fileName = [fileName copy];
        _mimeType = [mimeType copy];
        _completion = [completion copy];
        self.maxRetryCount = 1; // one retry on network/5xx
    }
    return self;
}

- (void)start
{
    [super start];
    if (self.isCancelled) { [self completeOperation]; return; }
    [self beginUploadAttempt:0];
}

- (void)beginUploadAttempt:(NSInteger)attempt
{
    self.attempt = attempt;
    if (self.isCancelled) { [self completeWithError:[NSError errorWithDomain:@"SeadocImageUploadOperation" code:-999 userInfo:@{NSLocalizedDescriptionKey:@"cancelled"}]]; return; }

    NSMutableURLRequest *req = [self buildMultipartRequest];
    if (!req) {
        [self completeWithError:[NSError errorWithDomain:@"SeadocImageUploadOperation" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"bad url"}]];
        return;
    }
    __weak typeof(self) wself = self;
    NSURLSessionDataTask *task = [self.connection sendPreparedRequest:req success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id  _Nonnull JSON) {
        __strong typeof(wself) sself = wself; if (!sself) return;
        if ([JSON isKindOfClass:NSDictionary.class]) {
            id list = ((NSDictionary *)JSON)[@"relative_path"];
            if ([list isKindOfClass:NSArray.class]) {
                sself.relativePaths = list;
                [sself completeWithError:nil];
                return;
            }
        }
        NSError *e = [NSError errorWithDomain:@"SeadocImageUploadOperation" code:-4 userInfo:@{NSLocalizedDescriptionKey:@"unexpected payload"}];
        [sself completeWithError:e];
    } failure:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id  _Nullable JSON, NSError * _Nullable error) {
        __strong typeof(wself) sself = wself; if (!sself) return;
        NSInteger status = response.statusCode;
        BOOL shouldRetry = [sself isRetryableError:error] || (status >= 500 && status <= 599);
        if (shouldRetry && sself.attempt < sself.maxRetryCount) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [sself beginUploadAttempt:(sself.attempt + 1)];
            });
            return;
        }
        [sself completeWithError:error ?: [NSError errorWithDomain:@"SeadocImageUploadOperation" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"upload failed"}]];
    }];
    if (task) {
        @synchronized (self.taskList) {
            [self.taskList addObject:task];
        }
    }
}

- (NSMutableURLRequest *)buildMultipartRequest
{
    NSString *base = self.seadocServerUrl ?: @"";
    if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length-1];
    if ([base hasSuffix:@"/seadoc"]) base = [base substringToIndex:base.length-7];
    if (![base hasSuffix:@"/seahub"]) base = [base stringByAppendingString:@"/seahub"];
    NSString *urlStr = [NSString stringWithFormat:@"%@/api/v2.1/seadoc/upload-image/%@/", base, self.docUUID];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return nil;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    NSString *boundary = [NSString stringWithFormat:@"Boundary-%u", arc4random_uniform(1000000000)];
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [req setValue:contentType forHTTPHeaderField:@"Content-Type"];
    if (self.seadocAccessToken.length > 0) {
        [req setValue:[NSString stringWithFormat:@"Token %@", self.seadocAccessToken] forHTTPHeaderField:@"Authorization"];
    }
    [req setValue:SEAFILE_VERSION forHTTPHeaderField:@"X-Seafile-Client-Version"];

    NSMutableData *body = [NSMutableData data];
    // file part
    [self appendString:[NSString stringWithFormat:@"--%@\r\n", boundary] toData:body];
    [self appendString:[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\n", self.fileName] toData:body];
    [self appendString:[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", self.mimeType] toData:body];
    [body appendData:self.fileData];
    [self appendString:@"\r\n" toData:body];

    // optional authorization form part (compat)
    [self appendString:[NSString stringWithFormat:@"--%@\r\n", boundary] toData:body];
    [self appendString:@"Content-Disposition: form-data; name=\"authorization\"\r\n\r\n" toData:body];
    NSString *authValue = [NSString stringWithFormat:@"Token %@", self.seadocAccessToken ?: @"" ];
    [self appendString:authValue toData:body];
    [self appendString:@"\r\n" toData:body];

    // end
    [self appendString:[NSString stringWithFormat:@"--%@--\r\n", boundary] toData:body];
    req.HTTPBody = body;
    return req;
}

- (void)appendString:(NSString *)string toData:(NSMutableData *)data
{
    [data appendData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)completeWithError:(NSError *)error
{
    self.error = error;
    SeadocImageUploadCompletion cb = self.completion;
    NSArray<NSString *> *paths = self.relativePaths;
    if (cb) {
        dispatch_async(dispatch_get_main_queue(), ^{
            cb(paths, error);
        });
    }
    [self completeOperation];
}

@end


