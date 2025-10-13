//  SeafDocCommentParser.m

#import "SeafDocCommentParser.h"
#import "SeafDocCommentContentItem.h"

@implementation SeafDocCommentParser

+ (NSAttributedString *)attributedContentFromComment:(NSString *)comment
{
    if (comment.length == 0) return [[NSAttributedString alloc] initWithString:@""];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSArray<NSString *> *paras = [comment componentsSeparatedByString:@"\n\n"];
    // textSize="14sp", textColor="#212529"
    NSDictionary *textAttrs = @{ 
        NSFontAttributeName: [UIFont systemFontOfSize:14], 
        NSForegroundColorAttributeName: [UIColor colorWithRed:0x21/255.0 green:0x25/255.0 blue:0x29/255.0 alpha:1.0]
    };

    NSRegularExpression *mdImg = [NSRegularExpression regularExpressionWithPattern:@"!\\\\?\\\\[\\\\]\\\\(([^\\\\)]+)\\\\)" options:0 error:nil];
    NSRegularExpression *htmlImg = [NSRegularExpression regularExpressionWithPattern:@"<img[^>]*src=\\\\\"([^\\\\\"]+)\\\\\"[^>]*>" options:NSRegularExpressionCaseInsensitive error:nil];

    for (NSUInteger i = 0; i < paras.count; i++) {
        NSString *p = paras[i];
        if (p.length == 0) continue;

        __block NSUInteger idx = 0;
        void (^appendText)(NSString *) = ^(NSString *t){ if (t.length>0) [result appendAttributedString:[[NSAttributedString alloc] initWithString:t attributes:textAttrs]]; };
        void (^appendImageURL)(NSString *) = ^(NSString *url){
            if (url.length == 0) return;
            NSTextAttachment *att = [NSTextAttachment new];
            att.bounds = CGRectMake(0, 0, 120, 80); // placeholder size; real async loading omitted in UI-only phase
            // Leave image empty for now; later we can async load by URL
            NSAttributedString *imgAttr = [NSAttributedString attributedStringWithAttachment:att];
            [result appendAttributedString:imgAttr];
        };

        // scan markdown images
        NSArray<NSTextCheckingResult *> *mdMatches = [mdImg matchesInString:p options:0 range:NSMakeRange(0, p.length)];
        NSArray<NSTextCheckingResult *> *htmlMatches = [htmlImg matchesInString:p options:0 range:NSMakeRange(0, p.length)];

        // merge process by positions
        NSMutableArray *all = [NSMutableArray array];
        for (NSTextCheckingResult *m in mdMatches) [all addObject:m];
        for (NSTextCheckingResult *m in htmlMatches) [all addObject:m];
        [all sortUsingComparator:^NSComparisonResult(NSTextCheckingResult *a, NSTextCheckingResult *b) {
            NSInteger da = a.range.location;
            NSInteger db = b.range.location;
            if (da < db) return NSOrderedAscending; if (da>db) return NSOrderedDescending; return NSOrderedSame;
        }];

        NSUInteger cursor = 0;
        for (NSTextCheckingResult *m in all) {
            if (m.range.location > cursor) {
                NSString *t = [p substringWithRange:NSMakeRange(cursor, m.range.location - cursor)];
                appendText(t);
            }
            NSString *url = nil;
            if (m.numberOfRanges > 1) {
                url = [p substringWithRange:[m rangeAtIndex:1]];
            }
            appendImageURL(url ?: @"");
            cursor = m.range.location + m.range.length;
        }
        if (cursor < p.length) {
            appendText([p substringFromIndex:cursor]);
        }
        if (i != paras.count - 1) {
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n" attributes:textAttrs]];
        }
    }
    return result.copy;
}

// Android-style: separate text and images (equivalent to Android's formatContent)
+ (NSArray<SeafDocCommentContentItem *> *)parseCommentToContentItems:(NSString *)comment
{
    if (comment.length == 0) return @[];
    
    NSMutableArray<SeafDocCommentContentItem *> *items = [NSMutableArray array];
    NSArray<NSString *> *paras = [comment componentsSeparatedByString:@"\n\n"];
    
    // imgPrefix = "<img", imgMdPrefix = "![]("
    NSRegularExpression *mdImg = [NSRegularExpression regularExpressionWithPattern:@"!\\[\\]\\(([^\\)]+)\\)" options:0 error:nil];
    NSRegularExpression *htmlImg = [NSRegularExpression regularExpressionWithPattern:@"<img[^>]*src=\"([^\"]+)\"[^>]*>" options:NSRegularExpressionCaseInsensitive error:nil];
    
    for (NSString *para in paras) {
        if (para.length == 0) continue;
        
        // Check whether the paragraph contains images
        NSArray<NSTextCheckingResult *> *mdMatches = [mdImg matchesInString:para options:0 range:NSMakeRange(0, para.length)];
        NSArray<NSTextCheckingResult *> *htmlMatches = [htmlImg matchesInString:para options:0 range:NSMakeRange(0, para.length)];
        
        if (mdMatches.count == 0 && htmlMatches.count == 0) {
            // Plain text paragraph
            SeafDocCommentContentItem *item = [SeafDocCommentContentItem itemWithType:SeafDocCommentContentTypeText content:para];
            [items addObject:item];
            continue;
        }
        
        // Merge and sort all image matches
        NSMutableArray *allMatches = [NSMutableArray array];
        for (NSTextCheckingResult *m in mdMatches) [allMatches addObject:m];
        for (NSTextCheckingResult *m in htmlMatches) [allMatches addObject:m];
        [allMatches sortUsingComparator:^NSComparisonResult(NSTextCheckingResult *a, NSTextCheckingResult *b) {
            if (a.range.location < b.range.location) return NSOrderedAscending;
            if (a.range.location > b.range.location) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        
        // Separate text and images
        NSUInteger cursor = 0;
        for (NSTextCheckingResult *match in allMatches) {
            // Add text before the image
            if (match.range.location > cursor) {
                NSString *text = [para substringWithRange:NSMakeRange(cursor, match.range.location - cursor)];
                if (text.length > 0) {
                    SeafDocCommentContentItem *textItem = [SeafDocCommentContentItem itemWithType:SeafDocCommentContentTypeText content:text];
                    [items addObject:textItem];
                }
            }
            
            // Add image URL
            if (match.numberOfRanges > 1) {
                NSString *imageURL = [para substringWithRange:[match rangeAtIndex:1]];
                // Trim potential whitespace
                imageURL = [imageURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (imageURL.length > 0 && ![imageURL.lowercaseString isEqualToString:@"null"]) {
                    SeafDocCommentContentItem *imageItem = [SeafDocCommentContentItem itemWithType:SeafDocCommentContentTypeImage content:imageURL];
                    [items addObject:imageItem];
                }
            }
            
            cursor = match.range.location + match.range.length;
        }
        
        // Add the remaining text
        if (cursor < para.length) {
            NSString *remainingText = [para substringFromIndex:cursor];
            if (remainingText.length > 0) {
                SeafDocCommentContentItem *textItem = [SeafDocCommentContentItem itemWithType:SeafDocCommentContentTypeText content:remainingText];
                [items addObject:textItem];
            }
        }
    }
    
    return items.copy;
}

@end

