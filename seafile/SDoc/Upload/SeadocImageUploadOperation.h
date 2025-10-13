//
//  SeadocImageUploadOperation.h
//

#import <Foundation/Foundation.h>
#import "SeafBaseOperation.h"

@class SeafConnection;

typedef void (^SeadocImageUploadCompletion)(NSArray<NSString *> * _Nullable relativePaths, NSError * _Nullable error);

@interface SeadocImageUploadOperation : SeafBaseOperation

@property (nonatomic, weak, readonly) SeafConnection *connection;
@property (nonatomic, copy, readonly) NSString *docUUID;
@property (nonatomic, copy, readonly) NSString *seadocServerUrl;
@property (nonatomic, copy, readonly) NSString *seadocAccessToken;
@property (nonatomic, copy, readonly) NSString *fileName;
@property (nonatomic, copy, readonly) NSString *mimeType;
@property (nonatomic, strong, readonly) NSData *fileData;

// Result
@property (nonatomic, strong, readonly) NSArray<NSString *> * _Nullable relativePaths;
@property (nonatomic, strong, readonly) NSError * _Nullable error;

- (instancetype)initWithConnection:(SeafConnection *)connection
                           docUUID:(NSString *)docUUID
                    seadocServerUrl:(NSString *)seadocServerUrl
                seadocAccessToken:(NSString *)seadocAccessToken
                          fileData:(NSData *)fileData
                           fileName:(NSString *)fileName
                           mimeType:(NSString *)mimeType
                         completion:(SeadocImageUploadCompletion)completion;

@end


