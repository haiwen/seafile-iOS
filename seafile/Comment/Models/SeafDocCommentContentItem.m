//  SeafDocCommentContentItem.m

#import "SeafDocCommentContentItem.h"

@implementation SeafDocCommentContentItem

+ (instancetype)itemWithType:(SeafDocCommentContentType)type content:(NSString *)content
{
    SeafDocCommentContentItem *item = [[SeafDocCommentContentItem alloc] init];
    item.type = type;
    item.content = content ?: @"";
    return item;
}

@end
