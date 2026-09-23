//
//  SeafFPItem.h
//  SeafFileProvider
//
//  NSFileProviderItem implementation for the replicated extension.
//

#import <Foundation/Foundation.h>
#import <FileProvider/FileProvider.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@class SeafRepo;
@class SeafFPRecord;
@class SeafFPDecoration;

NS_ASSUME_NONNULL_BEGIN

@interface SeafFPItem : NSObject <NSFileProviderItem>

@property (nonatomic, copy) NSFileProviderItemIdentifier itemIdentifier;
@property (nonatomic, copy) NSFileProviderItemIdentifier parentItemIdentifier;
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, copy) UTType *contentType;
@property (nonatomic, assign) NSFileProviderItemCapabilities capabilities;
@property (nonatomic, strong) NSFileProviderItemVersion *itemVersion;
@property (nonatomic, copy, nullable) NSNumber *documentSize;
@property (nonatomic, copy, nullable) NSNumber *childItemCount;
@property (nonatomic, copy, nullable) NSDate *contentModificationDate;
@property (nonatomic, copy, nullable) NSNumber *favoriteRank;
@property (nonatomic, copy, nullable) NSData *tagData;
@property (nonatomic, copy, nullable) NSDate *lastUsedDate;
@property (nonatomic, assign, readonly) BOOL isDirectory;

+ (instancetype)rootItemWithName:(NSString *)name;
+ (instancetype)trashItem;
+ (instancetype)itemForRepo:(SeafRepo *)repo;
+ (instancetype)itemForRecord:(SeafFPRecord *)record repoEditable:(BOOL)editable;

- (void)applyDecoration:(nullable SeafFPDecoration *)decoration;

+ (UTType *)contentTypeForFilename:(NSString *)filename;
+ (NSFileProviderItemVersion *)versionWithContent:(nullable NSString *)content metadata:(NSString *)metadata;

/// Write capabilities (step 3). Kept as a single switch for debugging.
+ (BOOL)writeOperationsEnabled;

@end

NS_ASSUME_NONNULL_END
