//  SDocPageOptionsModel.h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SDocPageOptionsModel : NSObject

@property (nonatomic, copy) NSString *seadocServerUrl;
@property (nonatomic, copy) NSString *seadocAccessToken;
@property (nonatomic, copy) NSString *docUuid;
@property (nonatomic, copy) NSString *latestContributor; // Email/username of the last modifier

- (BOOL)canUse;

+ (instancetype)fromJSONString:(NSString *)jsonStr;

@end

NS_ASSUME_NONNULL_END

