//
//  SeafWikiModel.m
//  seafile
//
//  Created on 2026/5/12.
//

#import "SeafWikiModel.h"

NSString * const SeafWikiTypeMine   = @"mine";
NSString * const SeafWikiTypeShared = @"shared";
NSString * const SeafWikiTypeOld    = @"old";
NSString * const SeafWikiTypeGroup  = @"group";

#pragma mark - SeafWikiInfo

@implementation SeafWikiInfo

- (instancetype)initWithWiki2JSON:(NSDictionary *)json {
    if (self = [super init]) {
        _wikiId       = [self stringValue:json[@"id"]];
        _isPublished  = [json[@"is_published"] boolValue];
        _name         = [self stringValue:json[@"name"]] ?: @"";
        _owner        = [self stringValue:json[@"owner"]];
        _ownerNickname = [self stringValue:json[@"owner_nickname"]];
        _ownerAvatarUrl = [self stringValue:json[@"owner_avatar_url"]];
        _permission   = [self stringValue:json[@"permission"]];
        _publicUrl    = [self stringValue:json[@"public_url"]];
        _slug         = [self stringValue:json[@"slug"]];
        _repoId       = [self stringValue:json[@"repo_id"]];
        _type         = [self stringValue:json[@"type"]];
        _updatedAt    = [self stringValue:json[@"updated_at"]];
        _createdAt    = [self stringValue:json[@"created_at"]];
        _groupId      = 0;
    }
    return self;
}

- (instancetype)initWithWiki1JSON:(NSDictionary *)json {
    if (self = [super init]) {
        _wikiId       = [NSString stringWithFormat:@"%@", json[@"id"]];
        _isPublished  = YES; // Old wikis are always published
        _name         = [self stringValue:json[@"name"]] ?: @"";
        _owner        = [self stringValue:json[@"owner"]];
        _ownerNickname = [self stringValue:json[@"owner_nickname"]];
        _ownerAvatarUrl = [self stringValue:json[@"owner_avatar_url"]];
        _permission   = [self stringValue:json[@"permission"]];
        _publicUrl    = [self stringValue:json[@"link"]];
        _slug         = [self stringValue:json[@"slug"]];
        _repoId       = [self stringValue:json[@"repo_id"]];
        _type         = SeafWikiTypeOld;
        _updatedAt    = [self stringValue:json[@"updated_at"]];
        _createdAt    = [self stringValue:json[@"created_at"]];
        _groupId      = -3;
        _groupName    = @"Old";
        _groupOwner   = nil;
    }
    return self;
}

/// Safely extract a string value from a JSON value (handles NSNull and numeric types)
- (nullable NSString *)stringValue:(id)value {
    if (!value || [value isKindOfClass:[NSNull class]]) return nil;
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return [value description];
}

@end

#pragma mark - SeafWikiGroup

@implementation SeafWikiGroup

- (instancetype)initWithTitle:(NSString *)title iconName:(nullable NSString *)iconName {
    if (self = [super init]) {
        _title = title;
        _iconName = iconName;
    }
    return self;
}

@end
