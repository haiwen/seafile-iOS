//  SDocPageOptionsModel.m

#import "SDocPageOptionsModel.h"

@implementation SDocPageOptionsModel

- (BOOL)canUse
{
    return self.seadocServerUrl.length > 0 && self.seadocAccessToken.length > 0 && self.docUuid.length > 0;
}

+ (instancetype)fromJSONString:(NSString *)jsonStr
{
    if (jsonStr.length == 0) return nil;
    NSData *d = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
    if (!d) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *dict = (NSDictionary *)obj;
    SDocPageOptionsModel *m = [SDocPageOptionsModel new];
    m.seadocServerUrl = [dict objectForKey:@"seadocServerUrl"] ?: @"";
    m.seadocAccessToken = [dict objectForKey:@"seadocAccessToken"] ?: @"";
    m.docUuid = [dict objectForKey:@"docUuid"] ?: @"";
    // Parse latestContributor, fallback to empty string
    id latestContributor = [dict objectForKey:@"latestContributor"];
    m.latestContributor = ([latestContributor isKindOfClass:NSString.class]) ? latestContributor : @"";
    return m;
}

@end

