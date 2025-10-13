//  OutlineItemModel.h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OutlineItemModel : NSObject

@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSArray<OutlineItemModel *> *children;

+ (NSArray<OutlineItemModel *> *)arrayFromJSONString:(NSString *)jsonStr;

@end

NS_ASSUME_NONNULL_END

