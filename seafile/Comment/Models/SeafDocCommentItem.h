//  SeafDocCommentItem.h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SeafDocCommentContentItem;

@interface SeafDocCommentItem : NSObject

@property (nonatomic, assign) long long commentId;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) NSString *timeString;
@property (nonatomic, strong, nullable) NSDate *createdAtDate; // Added: original time for stable sorting
@property (nonatomic, strong, nullable) NSAttributedString *attributedContent;  // Kept for compatibility
@property (nonatomic, assign) BOOL resolved;

// Android-style: content item list
@property (nonatomic, strong, nullable) NSArray<SeafDocCommentContentItem *> *contentItems;

+ (instancetype)itemWithAuthor:(NSString *)author
                     avatarURL:(NSString *)avatarURL
                    timeString:(NSString *)timeString
              attributedContent:(NSAttributedString *)attributedContent
                        itemId:(long long)itemId
                       resolved:(BOOL)resolved;

// Android-style: use content item list
+ (instancetype)itemWithAuthor:(NSString *)author
                     avatarURL:(NSString *)avatarURL
                    timeString:(NSString *)timeString
                  contentItems:(NSArray<SeafDocCommentContentItem *> *)contentItems
                        itemId:(long long)itemId
                       resolved:(BOOL)resolved;

@end

NS_ASSUME_NONNULL_END

