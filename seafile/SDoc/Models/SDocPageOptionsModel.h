//  SDocPageOptionsModel.h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SDocPageOptionsModel : NSObject

@property (nonatomic, copy) NSString *seadocServerUrl;
@property (nonatomic, copy) NSString *seadocAccessToken;
@property (nonatomic, copy) NSString *docUuid;

- (BOOL)canUse;

+ (instancetype)fromJSONString:(NSString *)jsonStr;

@end

NS_ASSUME_NONNULL_END

