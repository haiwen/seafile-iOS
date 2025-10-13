//  SeafDocCommentItem.m

#import "SeafDocCommentItem.h"

@implementation SeafDocCommentItem

+ (instancetype)itemWithAuthor:(NSString *)author
                     avatarURL:(NSString *)avatarURL
                    timeString:(NSString *)timeString
              attributedContent:(NSAttributedString *)attributedContent
                        itemId:(long long)itemId
                       resolved:(BOOL)resolved
{
    SeafDocCommentItem *item = [SeafDocCommentItem new];
    item.author = author ?: @"";
    item.avatarURL = avatarURL ?: @"";
    item.timeString = timeString ?: @"";
    item.attributedContent = attributedContent ?: [[NSAttributedString alloc] initWithString:@""];
    item.commentId = itemId;
    item.resolved = resolved;
    return item;
}

// Android-style: use content item list
+ (instancetype)itemWithAuthor:(NSString *)author
                     avatarURL:(NSString *)avatarURL
                    timeString:(NSString *)timeString
                  contentItems:(NSArray<SeafDocCommentContentItem *> *)contentItems
                        itemId:(long long)itemId
                       resolved:(BOOL)resolved
{
    SeafDocCommentItem *item = [SeafDocCommentItem new];
    item.author = author ?: @"";
    item.avatarURL = avatarURL ?: @"";
    item.timeString = timeString ?: @"";
    item.contentItems = contentItems;
    item.commentId = itemId;
    item.resolved = resolved;
    return item;
}

@end

