//
//  SeafWikiModel.h
//  seafile
//
//  Created on 2026/5/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Type constants for wiki categorization
extern NSString * const SeafWikiTypeMine;
extern NSString * const SeafWikiTypeShared;
extern NSString * const SeafWikiTypeOld;
extern NSString * const SeafWikiTypeGroup;

#pragma mark - SeafWikiInfo

/// Unified wiki info model (covers both new wiki2 and legacy wiki1 data)
@interface SeafWikiInfo : NSObject

@property (nonatomic, copy) NSString *wikiId;
@property (nonatomic, assign) BOOL isPublished;
@property (nonatomic, assign) long long groupId;
@property (nonatomic, copy, nullable) NSString *groupName;
@property (nonatomic, copy, nullable) NSString *groupOwner;

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *owner;
@property (nonatomic, copy, nullable) NSString *ownerNickname;
@property (nonatomic, copy, nullable) NSString *ownerAvatarUrl;
@property (nonatomic, copy, nullable) NSString *permission;
@property (nonatomic, copy, nullable) NSString *publicUrl;
@property (nonatomic, copy, nullable) NSString *slug;
@property (nonatomic, copy, nullable) NSString *repoId;
@property (nonatomic, copy, nullable) NSString *type;       // "mine", "shared", or set to SeafWikiTypeOld
@property (nonatomic, copy, nullable) NSString *updatedAt;
@property (nonatomic, copy, nullable) NSString *createdAt;

/// Initialize from a wiki2 API JSON dictionary
- (instancetype)initWithWiki2JSON:(NSDictionary *)json;

/// Initialize from a legacy wiki1 API JSON dictionary
- (instancetype)initWithWiki1JSON:(NSDictionary *)json;

@end

#pragma mark - SeafWikiGroup

/// Represents a display group header in the wiki list (e.g. "My Wiki", "Shared", group name)
@interface SeafWikiGroup : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *iconName;

- (instancetype)initWithTitle:(NSString *)title iconName:(nullable NSString *)iconName;

@end

NS_ASSUME_NONNULL_END
