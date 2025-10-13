//  SeafDocCommentContentItem.h
//  Corresponds to Android's RichEditText.RichContentModel

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SeafDocCommentContentType) {
    SeafDocCommentContentTypeText = 0,   //  type = 0
    SeafDocCommentContentTypeImage = 1   //  type = 1
};

@interface SeafDocCommentContentItem : NSObject

@property (nonatomic, assign) SeafDocCommentContentType type;
@property (nonatomic, copy) NSString *content;

+ (instancetype)itemWithType:(SeafDocCommentContentType)type content:(NSString *)content;

@end
