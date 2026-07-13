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

/// Format a date value for display (align Android MetadataViewUtils.parseDate / buildEditableDate).
/// Uses metadata.data.format when present; otherwise yyyy-MM-dd HH:mm:ss.
+ (NSString *)displayDateString:(id)value withMetadata:(NSDictionary * _Nullable)metadata;

/// Format a date value to yyyy-MM-dd HH:mm:ss (align Android DateFormatType.DATE_YMD_HMS)
+ (NSString *)formatDateValue:(id)value;

/// Format a number using metadata config (align Android MetadataViewUtils.getFormattedNumber)
/// Supports: format (number, percent, yuan, dollar, euro, custom_currency), precision, thousands, decimal
+ (NSString *)formatNumber:(NSNumber *)number withMetadata:(NSDictionary *)metadata;

/// Format file size to human-readable string (e.g. "1.5 MB")
+ (NSString *)readableSize:(long long)size;

/// Fallback colored option for known _status codes (align Android status colors)
+ (NSDictionary * _Nullable)statusOptionForCode:(NSString *)code;

/// Merge `_location` with `_location_translated` (align Android checkLocationTranslated)
+ (id _Nullable)mergedGeolocationValue:(id _Nullable)locationValue translated:(id _Nullable)translated;

/// Format geolocation for display (align Android GeoLocationModel.getText).
/// Only resolves when metadata geo_format is `lng_lat`.
+ (NSString *)geolocationDisplayStringFromValue:(id _Nullable)value metadata:(NSDictionary * _Nullable)metadata;

@end

NS_ASSUME_NONNULL_END

