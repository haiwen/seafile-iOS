//
//  SeafBaseModel.h
//  Seafile
//
//  Created by henry on 2025/1/23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafBaseModel : NSObject

@property (nonatomic, copy, nullable) NSString *oid;        // Object ID
@property (nonatomic, copy, nullable) NSString *repoId;     // Repository ID
@property (nonatomic, copy, nullable) NSString *name;       // Entry name
@property (nonatomic, copy, nullable) NSString *path;       // Path in the repository
@property (nonatomic, copy, nullable) NSString *mime;       // MIME type
@property (nonatomic, copy, nullable) NSString *ooid;       // Old object ID
@property (nonatomic, copy, nullable) NSString *shareLink;  // Share link

/**
 Initialize model

 @param oid Object ID
 @param repoId Repository ID
 @param name Folder or file name
 @param path Path in the repository
 @param mime MIME type
 */
- (instancetype)initWithOid:(nullable NSString *)oid
                     repoId:(nullable NSString *)repoId
                       name:(nullable NSString *)name
                       path:(nullable NSString *)path
                       mime:(nullable NSString *)mime NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
