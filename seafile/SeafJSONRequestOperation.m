//
//  SeafJSONRequestOperation.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafJSONRequestOperation.h"
#import "AFJSONUtilities.h"
#import "Debug.h"

static dispatch_queue_t af_json_request_operation_processing_queue;
static dispatch_queue_t json_request_operation_processing_queue() {
    if (af_json_request_operation_processing_queue == NULL) {
        af_json_request_operation_processing_queue = dispatch_queue_create("com.alamofire.networking.json-request.processing", 0);
    }

    return af_json_request_operation_processing_queue;
}

@interface SeafJSONRequestOperation ()
@property (readwrite, nonatomic, retain) id responseJSON;
@property (readwrite, nonatomic, retain) NSError *JSONError;

@end

@implementation SeafJSONRequestOperation
@synthesize responseJSON = _responseJSON;
@synthesize JSONError = _JSONError;

+ (SeafJSONRequestOperation *)JSONRequestOperationWithRequest:(NSURLRequest *)urlRequest
                                                      success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data))success
                                                      failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, NSData *data))failure
{
    SeafJSONRequestOperation *requestOperation = [[self alloc] initWithRequest:urlRequest];
    [requestOperation setAuthenticationAgainstProtectionSpaceBlock:^(NSURLConnection *connection, NSURLProtectionSpace *protectionSpace) {
        return YES;
    }];
    [requestOperation setAuthenticationChallengeBlock:^(NSURLConnection *connection, NSURLAuthenticationChallenge *challenge) {
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    }];
    [requestOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        if (success) {
            Debug("%d, %@\n", [operation.response statusCode], operation.request.URL);
            success (operation.request, operation.response, responseObject, operation.responseData);
        }
    }
                                            failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                                                if (failure) {
                                                    Warning("%@,err=%d, %@,%@\n", operation.request.URL, error.code, error.localizedDescription, [[NSString alloc] initWithData:operation.responseData encoding:NSUTF8StringEncoding]);
                                                    failure (operation.request, operation.response, error, operation.responseData);
                                                }
                                            }
     ];

    return requestOperation;
}


+ (BOOL)canProcessRequest:(NSURLRequest *)request
{
    return YES;
}

- (id)initWithRequest:(NSURLRequest *)urlRequest
{
    self = [super initWithRequest:urlRequest];
    if (!self) {
        return nil;
    }

    return self;
}

- (id)responseJSON
{
    if (!_responseJSON && [self isFinished]) {
        NSError *error = nil;
        if ([self.responseData length] == 0) {
            self.responseJSON = nil;
        }
        else {
            self.responseJSON = AFJSONDecode(self.responseData, &error);
        }

        self.JSONError = error;
    }

    if (!_responseJSON) {
        id responce;
        NSString *rawData = [[NSString alloc] initWithData:self.responseData
                                                  encoding:NSUTF8StringEncoding];
        if ([rawData hasPrefix:@"\""] && [rawData hasSuffix:@"\""]) {
            responce = [rawData substringWithRange:NSMakeRange(1, [rawData length] - 2)];
            self.JSONError = nil;
            self.responseJSON = responce;
        }
        else {
            NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
            NSNumber *numberResponce = [f numberFromString:rawData];
            if (numberResponce) {
                responce= numberResponce;
                self.JSONError = nil;
                self.responseJSON = responce;
            } else
                responce = self.responseData;
        }
        return responce;
    }
    else {
        return _responseJSON;
    }
}

- (NSError *)error
{
    if (_JSONError) {
        return _JSONError;
    }
    else {
        return [super error];
    }
}

#pragma clang diagnostic ignored "-Warc-retain-cycles"
- (void)setCompletionBlockWithSuccess:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                              failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure
{
    self.completionBlock = ^ {
        if (self.isCancelled) {
            return;
        }

        if (self.error) {
            if (failure) {
                dispatch_async (dispatch_get_main_queue (), ^(void) {
                    failure (self, self.error);
                });
            }
        }
        else {
            dispatch_async (json_request_operation_processing_queue (), ^(void) {
                id JSON = self.responseJSON;
                dispatch_async (dispatch_get_main_queue (), ^(void) {
                    if (self.JSONError) {
                        if (failure) {
                            failure (self, self.JSONError);
                        }
                    } else {
                        if (success) {
                            success (self, JSON);
                        }
                    }
                });
            });
        }
    };
}

@end
