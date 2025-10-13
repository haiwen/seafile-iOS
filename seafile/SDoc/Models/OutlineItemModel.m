//  OutlineItemModel.m

#import "OutlineItemModel.h"

@implementation OutlineItemModel

+ (NSArray<OutlineItemModel *> *)arrayFromJSONString:(NSString *)jsonStr
{
    if (jsonStr.length == 0) return @[];
    NSData *d = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
    if (!d) return @[];
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    if (![obj isKindOfClass:[NSArray class]]) return @[];
    NSArray *arr = (NSArray *)obj;
    NSMutableArray *res = [NSMutableArray arrayWithCapacity:arr.count];
    for (id item in arr) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *dict = (NSDictionary *)item;
        OutlineItemModel *m = [OutlineItemModel new];
        m.type = [dict objectForKey:@"type"] ?: @"";
        m.text = [dict objectForKey:@"text"] ?: @"";
        NSArray *children = [dict objectForKey:@"children"];
        if ([children isKindOfClass:[NSArray class]]) {
            NSData *cd = [NSJSONSerialization dataWithJSONObject:children options:0 error:nil];
            NSString *cstr = [[NSString alloc] initWithData:cd encoding:NSUTF8StringEncoding];
            m.children = [OutlineItemModel arrayFromJSONString:cstr];
        } else {
            m.children = @[];
        }
        [res addObject:m];
    }
    return res.copy;
}

@end

