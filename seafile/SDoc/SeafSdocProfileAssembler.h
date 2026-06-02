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

/// Build detailsSettings visibility map from metadataConfig (align Android FileProfileConfigModel.getDetailsSettingsMap)
/// Returns NSDictionary<key, @(BOOL)> where YES = field is shown
+ (NSDictionary *)buildDetailsSettingsMapFromConfig:(NSDictionary *)metadataConfig metaEnabled:(BOOL)metaEnabled;

/// Shared date formatters for parsing date strings (reusable by editor)
+ (NSArray<NSDateFormatter *> *)sharedParseDateFormatters;

/// Format a number using metadata config (align Android MetadataViewUtils.getFormattedNumber)
/// Supports: format (number, percent, yuan, dollar, euro, custom_currency), precision, thousands, decimal
+ (NSString *)formatNumber:(NSNumber *)number withMetadata:(NSDictionary *)metadata;

/// Format file size to human-readable string (e.g. "1.5 MB")
+ (NSString *)readableSize:(long long)size;

@end

NS_ASSUME_NONNULL_END

