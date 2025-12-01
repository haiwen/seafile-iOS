//  SeafDocsCommentService.h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SeafConnection;

@interface SeafDocsCommentService : NSObject

// Designated initializer; falls back to global connection if nil
- (instancetype)initWithConnection:(SeafConnection * _Nullable)connection;

// Minimal signatures; implement with proper networking as needed later
- (void)getElementsWithDocUUID:(NSString *)uuid seadocServer:(NSString *)server token:(NSString *)token completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;
- (void)getCommentsWithDocUUID:(NSString *)uuid seadocServer:(NSString *)server token:(NSString *)token completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;

// Post a new root comment (element_id = "0")
- (void)postCommentForDocUUID:(NSString *)uuid
                 seadocServer:(NSString *)server
                        token:(NSString *)token
                      comment:(NSString *)comment
                       author:(NSString *)author
                    updatedAt:(NSString *)updatedAt
                   completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;

// Mark resolved
- (void)markResolvedForDocUUID:(NSString *)uuid
                   commentId:(long long)commentId
                 seadocServer:(NSString *)server
                        token:(NSString *)token
                   completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;

// Delete comment
- (void)deleteCommentForDocUUID:(NSString *)uuid
                      commentId:(long long)commentId
                    seadocServer:(NSString *)server
                           token:(NSString *)token
                      completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;

// Upload image (multipart). fileData/mime/fileName are required. Returns relative_path list
- (void)uploadImageForDocUUID:(NSString *)uuid
                  seadocServer:(NSString *)server
                         token:(NSString *)token
                       fileData:(NSData *)fileData
                        mimeType:(NSString *)mime
                        fileName:(NSString *)fileName
                      completion:(void(^)(NSDictionary * _Nullable resp, NSError * _Nullable error))completion;

// Get participants (users who have been mentioned in this doc)
// API: /api/v2.1/seadoc/participants/{docUuid}/
// Uses seahub server (via SeafConnection), not seadoc server
- (void)getParticipantsWithDocUUID:(NSString *)uuid
                         completion:(void(^)(NSArray<NSDictionary *> * _Nullable participants, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

