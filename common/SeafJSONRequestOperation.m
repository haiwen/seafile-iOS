//
//  SeafJSONRequestOperation.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafJSONRequestOperation.h"
#import "Utils.h"
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
    Debug("request :%@", urlRequest.URL);
    SeafJSONRequestOperation *requestOperation = [[self alloc] initWithRequest:urlRequest];
    [requestOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        if (success) {
            Debug("%ld, %@\n", (long)[operation.response statusCode], operation.request.URL);
            success (operation.request, operation.response, responseObject, operation.responseData);
        }
    }
                                            failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                                                if (failure) {
                                                    Warning("%@,err=%ld, %@,%@\n", operation.request.URL, (long)error.code, error.localizedDescription, [[NSString alloc] initWithData:operation.responseData encoding:NSUTF8StringEncoding]);
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
        } else {
            self.responseJSON = [Utils JSONDecode:self.responseData error:&error];
        }
        self.JSONError = error;
    }
    return _responseJSON;
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
                        if (failure)   failure (self, self.JSONError);
                    } else {
                        long code = self.response.statusCode / 100;
                        if (code != 2 && code != 3) {
                            NSError *err = [NSError errorWithDomain:NSOSStatusErrorDomain code:self.response.statusCode userInfo:nil];
                            if (failure)    failure (self, err);
                            return;
                        }
                        if (success)  success (self, JSON);
                    }
                });
            });
        }
    };
}

@end
