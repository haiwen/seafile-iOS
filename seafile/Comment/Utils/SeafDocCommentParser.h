//  SeafDocCommentParser.h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SeafDocCommentContentItem;

@interface SeafDocCommentParser : NSObject

// Build attributed content from raw comment string.
// Supports text paragraphs separated by "\n\n", markdown images: ![](url), and <img src="..."> tags.
+ (NSAttributedString *)attributedContentFromComment:(NSString *)comment;

// Android-style: separate text and images (equivalent to Android's formatContent)
// Parse comment string to content items list (text and images separated)
+ (NSArray<SeafDocCommentContentItem *> *)parseCommentToContentItems:(NSString *)comment;

@end

NS_ASSUME_NONNULL_END

