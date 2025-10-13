//  SeafImageAttachment.h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafImageAttachment : NSTextAttachment

@property (nonatomic, copy, nullable) NSString *uploadedURL; // set after upload success

@end

NS_ASSUME_NONNULL_END

