//  SeafSdocUserMapper.m
//
#import "SeafSdocUserMapper.h"

@implementation SeafSdocUserMapper

+ (NSDictionary<NSString *,NSString *> *)normalizeUserDict:(NSDictionary *)rawUser
{
    if (![rawUser isKindOfClass:[NSDictionary class]]) {
        return @{ @"name": @"", @"email": @"", @"avatarURL": @"" };
    }
    id name = rawUser[@"name"];
    if (![name isKindOfClass:NSString.class] || [name length] == 0) name = rawUser[@"display_name"];
    if (![name isKindOfClass:NSString.class] || [name length] == 0) name = rawUser[@"username"];
    if (![name isKindOfClass:NSString.class]) name = @"";
    
    id email = rawUser[@"email"];
    if (![email isKindOfClass:NSString.class] || [email length] == 0) email = rawUser[@"contact_email"];
    if (![email isKindOfClass:NSString.class] || [email length] == 0) email = rawUser[@"user_email"];
    if (![email isKindOfClass:NSString.class] || [email length] == 0) email = rawUser[@"contactEmail"];
    if (![email isKindOfClass:NSString.class]) email = @"";
    
    id avatar = rawUser[@"avatar_url"];
    if (![avatar isKindOfClass:NSString.class] || [avatar length] == 0) avatar = rawUser[@"avatarUrl"];
    if (![avatar isKindOfClass:NSString.class]) avatar = @"";
    
    return @{
        @"name": name,
        @"email": email,
        @"avatarURL": avatar
    };
}

@end


