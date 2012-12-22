//
//  SeafJSONRequestOperation.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "AFHTTPRequestOperation.h"

@interface SeafJSONRequestOperation : AFHTTPRequestOperation {
@private
    id _responseJSON;
    NSError *_JSONError;
}

@property (readonly, nonatomic, retain) id responseJSON;


+ (SeafJSONRequestOperation *)JSONRequestOperationWithRequest:(NSURLRequest *)urlRequest
                                                      success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data))success
                                                      failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, NSData *data))failure;

@end
