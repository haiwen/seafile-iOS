#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SeafFileProfileAggregate;

@interface SeafSdocProfileAssembler : NSObject

/// Build view-ready rows from aggregated JSON (Android-compatible rules)
/// @param aggregate A dictionary containing keys: fileDetail, metadataConfig, recordWrapper, relatedUsers, tagWrapper
/// @return NSArray of row dictionaries. Row schema:
///   title: NSString*
///   icon: NSString* (logical icon name)
///   type: NSString* (text|number|date|collaborator|single_select|multiple_select|rate|geolocation|checkbox|long_text|duration|email|url)
///   values: NSArray<NSDictionary*>* (per-type payload, e.g., {text, imageUrl, color, textColor, selected, ratingMax, ratingSelected, ...})
+ (NSArray<NSDictionary *> *)buildRowsFromAggregate:(NSDictionary *)aggregate;

/// Convenience: build view-ready rows directly from the aggregate model object
+ (NSArray<NSDictionary *> *)buildRowsFromProfileAggregate:(SeafFileProfileAggregate *)aggregate;

@end

NS_ASSUME_NONNULL_END

