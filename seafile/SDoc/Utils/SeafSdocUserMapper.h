//  SeafSdocUserMapper.h
//
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A small utility to normalize user dictionaries from various SDoc endpoints to a unified schema:
 { name, email, avatarURL }
 
 Input dictionary may contain keys like: name/display_name/username, email/contact_email/user_email, avatar_url/avatarUrl.
 */
@interface SeafSdocUserMapper : NSObject

// Normalize a single raw user dictionary into { name, email, avatarURL }. Missing fields become empty strings.
+ (NSDictionary<NSString *, NSString *> *)normalizeUserDict:(NSDictionary *)rawUser;

@end

NS_ASSUME_NONNULL_END


