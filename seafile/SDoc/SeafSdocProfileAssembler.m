//  SeafSdocProfileAssembler.m

#import "SeafSdocProfileAssembler.h"
#import "SeafSdocUserMapper.h"

@implementation SeafSdocProfileAssembler

// MARK: - Shared formatters (performance)

// Cached date formatters for parsing common patterns
+ (NSArray<NSDateFormatter *> *)sharedParseDateFormatters
{
    static NSArray<NSDateFormatter *> *parsers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *patterns = @[
            @"yyyy-MM-dd HH:mm:ss.SSSXXX",
            @"yyyy-MM-dd HH:mm:ssXXX",
            @"yyyy-MM-dd HH:mm:ss.SSS",
            @"yyyy-MM-dd HH:mm:ss",
            @"yyyy-MM-dd HH:mm",
            @"yyyy-MM-dd"
        ];
        NSMutableArray *arr = [NSMutableArray arrayWithCapacity:patterns.count];
        for (NSString *p in patterns) {
            NSDateFormatter *fmt = [NSDateFormatter new];
            fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            fmt.dateFormat = p;
            [arr addObject:fmt];
        }
        parsers = [arr copy];
    });
    return parsers;
}

// Cached date formatter for output
+ (NSDateFormatter *)sharedOutputDateFormatter
{
    static NSDateFormatter *fmt;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [NSDateFormatter new];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    return fmt;
}

// Cached number formatter for readableSize
+ (NSNumberFormatter *)sharedSizeNumberFormatter
{
    static NSNumberFormatter *fmt;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [NSNumberFormatter new];
        fmt.numberStyle = NSNumberFormatterDecimalStyle;
        fmt.minimumFractionDigits = 0;
        fmt.maximumFractionDigits = 1; // match Android DecimalFormat "#,##0.#"
    });
    return fmt;
}

+ (NSArray<NSDictionary *> *)buildRowsFromAggregate:(NSDictionary *)aggregate
{
    if (![aggregate isKindOfClass:[NSDictionary class]]) {
        return @[];
    }

    NSDictionary *fileDetail = aggregate[@"fileDetail"];
    NSDictionary *metadataConfig = aggregate[@"metadataConfig"] ?: @{};
    NSDictionary *recordWrapper = aggregate[@"recordWrapper"];
    NSDictionary *relatedUsers = aggregate[@"relatedUsers"];
    NSDictionary *tagWrapper = aggregate[@"tagWrapper"];

    BOOL metaEnabled = [metadataConfig[@"enabled"] boolValue];

    
    // Prepare metadata/results (fallback if needed)
    NSArray *metadata = [recordWrapper objectForKey:@"metadata"];
    NSArray *results = [recordWrapper objectForKey:@"results"];
    NSDictionary *singleResult = (results.count > 0 ? results.firstObject : nil);

    // Prepare effective related users (may be overridden in fallback)
    NSDictionary *effectiveRelatedUsers = relatedUsers;

    if (!metaEnabled || ![metadata isKindOfClass:[NSArray class]] || metadata.count == 0 || ![singleResult isKindOfClass:[NSDictionary class]]) {
        // build fallback with 3 fields: _size, _file_modifier, _file_mtime
        NSMutableArray *fallbackMetadata = [NSMutableArray array];
        [fallbackMetadata addObject:@{ @"key": @"_size", @"name": @"_size", @"type": @"number" }];
        [fallbackMetadata addObject:@{ @"key": @"_file_modifier", @"name": @"_file_modifier", @"type": @"text" }];
        [fallbackMetadata addObject:@{ @"key": @"_file_mtime", @"name": @"_file_mtime", @"type": @"date" }];

        id size = fileDetail[@"size"] ?: @(0);
        id modifier = fileDetail[@"last_modifier_email"] ?: @"";
        id mtime = fileDetail[@"last_modified"] ?: @"";
        NSDictionary *fallbackResult = @{ @"_size": size, @"_file_modifier": modifier, @"_file_mtime": mtime };
        long long fallbackSz = 0;
        if ([size isKindOfClass:[NSNumber class]]) fallbackSz = [(NSNumber *)size longLongValue];

        metadata = fallbackMetadata;
        singleResult = fallbackResult;

        // Fallback related users from fileDetail (align Android default user)
        NSString *defName = (fileDetail[@"last_modifier_name"] ?: @"");
        NSString *defAvatar = (fileDetail[@"last_modifier_avatar"] ?: @"");
        NSString *defEmail = (fileDetail[@"last_modifier_email"] ?: @"");
        NSString *defContact = (fileDetail[@"last_modifier_contact_email"] ?: @"");
        NSDictionary *defaultUser = @{ @"name": defName,
                                       @"avatar_url": defAvatar,
                                       @"email": defEmail,
                                       @"contact_email": defContact };
        effectiveRelatedUsers = @{ @"user_list": @[ defaultUser ] };
        
    }

    // Move _size to top if present
    NSMutableArray *orderedMetadata = [NSMutableArray arrayWithArray:metadata];
    NSInteger sizeIndex = NSNotFound;
    for (NSInteger i = 0; i < orderedMetadata.count; i++) {
        NSDictionary *m = orderedMetadata[i];
        if ([[m objectForKey:@"key"] isKindOfClass:[NSString class]] && [m[@"key"] isEqualToString:@"_size"]) {
            sizeIndex = i; break;
        }
    }
    if (sizeIndex != NSNotFound && sizeIndex != 0) {
        NSDictionary *sizeMeta = orderedMetadata[sizeIndex];
        [orderedMetadata removeObjectAtIndex:sizeIndex];
        [orderedMetadata insertObject:sizeMeta atIndex:0];
    }

    // whitelist for underscore fields
    NSSet *fixedKeys = [self fixedUnderscoreKeys];

    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];

    for (NSDictionary *m in orderedMetadata) {
        NSString *key = [m objectForKey:@"key"];
        NSString *name = [m objectForKey:@"name"] ?: key;
        NSString *rawType = [m objectForKey:@"type"] ?: @"text";
        NSString *type = [self normalizeType:rawType key:key];

        if ([key isKindOfClass:[NSString class]] && [key hasPrefix:@"_"]) {
            if (![fixedKeys containsObject:key]) {
                continue; // skip non-whitelisted underscore fields
            }
        }

        //  only use 'name' to fetch value from records
        id rawValue = singleResult[name];
        // value resolution uses 'name' for Android compatibility

        // special: _file_modifier → collaborator with [email]
        if ([key isEqualToString:@"_file_modifier"]) {
            type = @"collaborator";
            if (rawValue && [rawValue isKindOfClass:[NSString class]] && [((NSString *)rawValue) length] > 0) {
                rawValue = @[ rawValue ];
            } else if (![rawValue isKindOfClass:[NSArray class]]) {
                rawValue = @[];
            }
            
        }

        // Title
        NSString *title = [self titleForKey:key fallback:name];
        NSString *icon = [self iconForType:type];
        if ([key isEqualToString:@"_tags"]) {
            icon = @"tag-filled"; // use dedicated tag icon per design
        }

        // Fallback: for geolocation, if _location is empty, try _location_translated
        if ((rawValue == nil || rawValue == (id)[NSNull null]) && [key isEqualToString:@"_location"]) {
            id alt = singleResult[@"_location_translated"];
            if (alt) rawValue = alt;
        }
        NSArray *valueCells = [self renderValueCellsForType:type metadata:m key:key value:rawValue metadataConfig:metadataConfig tagWrapper:tagWrapper relatedUsers:effectiveRelatedUsers];
        if (valueCells.count == 0) {
            // except RATE, use structured empty marker (keep legacy "empty" for compatibility)
            if (![type isEqualToString:@"rate"]) {
                valueCells = @[ @{ @"isEmpty": @YES, @"text": @"empty" } ];
            }
        }

        [rows addObject:@{
            @"title": title ?: name ?: key ?: @"",
            @"icon": icon ?: @"text",
            @"type": type ?: @"text",
            @"values": valueCells ?: @[]
        }];
    }

    return rows;
}

#pragma mark - Helpers

// Shared fixed underscore keys
+ (NSSet *)fixedUnderscoreKeys
{
    static NSSet *s; static dispatch_once_t onceToken; dispatch_once(&onceToken, ^{
        s = [NSSet setWithArray:@[@"_size", @"_file_modifier", @"_file_mtime", @"_owner", @"_description", @"_collaborators", @"_reviewer", @"_status", @"_rate", @"_tags", @"_location"]];
    });
    return s;
}

+ (NSString *)titleForKey:(NSString *)key fallback:(NSString *)fallback
{
    static NSDictionary *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"_description": @"description",
            @"_file_modifier": @"_last_modifier",
            @"_file_mtime": @"_last_modified_time",
            @"_status": @"_file_status",
            @"_collaborators": @"_file_collaborators",
            @"_size": @"_size",
            @"_reviewer": @"_reviewer",
            @"_in_progress": @"_in_progress",
            @"_in_review": @"_in_review",
            @"_done": @"_done",
            @"_outdated": @"_outdated",
            @"_tags": @"_tags",
            @"_owner": @"_owner",
            @"_rate": @"_file_rate",
            @"_location": @"_location"
        };
    });
    NSString *v = map[key];
    return v ?: fallback;
}

+ (NSString *)iconForType:(NSString *)type
{
    static NSDictionary *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"text": @"text",
            @"collaborator": @"group",
            @"image": @"gallery",
            @"file": @"ic_file_alt_solid",
            @"date": @"date",
            @"single_select": @"check-box",
            @"duration": @"time",
            @"multiple_select": @"multiple-select",
            @"checkbox": @"single-select",
            @"geolocation": @"location",
            @"email": @"email",
            @"long_text": @"long-text",
            @"number": @"number",
            @"rate": @"star",
            @"url": @"ic_url",
            @"link": @"ic_links"
        };
    });
    NSString *v = map[type];
    return v ?: @"text";
}

+ (NSArray<NSDictionary *> *)renderValueCellsForType:(NSString *)type
                                            metadata:(NSDictionary *)metadata
                                                 key:(NSString *)key
                                               value:(id)value
                                     metadataConfig:(NSDictionary *)metadataConfig
                                         tagWrapper:(NSDictionary *)tagWrapper
                                       relatedUsers:(NSDictionary *)relatedUsers
{
    if ([type isEqualToString:@"text"] || [type isEqualToString:@"long_text"] || [type isEqualToString:@"duration"] || [type isEqualToString:@"email"] || [type isEqualToString:@"url"]) {
        if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
            return @[ @{ @"text": value } ];
        }
        return @[];
    }

        if ([type isEqualToString:@"number"]) {
        if ([key isEqualToString:@"_size"]) {
            long long sz = 0;
            if ([value isKindOfClass:[NSNumber class]]) sz = [(NSNumber *)value longLongValue];
            NSString *readable = [self readableSize:sz];
            return @[ @{ @"text": readable } ];
        }
        if ([value isKindOfClass:[NSNumber class]]) {
            NSNumber *n = (NSNumber *)value;
            BOOL isInteger = (llabs(n.longLongValue) == llabs((long long)llround(n.doubleValue)));
            NSString *t = isInteger ? [NSString stringWithFormat:@"%lld", n.longLongValue] : [NSString stringWithFormat:@"%g", n.doubleValue];
            return @[ @{ @"text": t } ];
        }
        return @[];
    }

    if ([type isEqualToString:@"date"]) {
        NSString *formatted = [self formatDateValue:value];
        if (formatted.length > 0) return @[ @{ @"text": formatted } ];
        return @[];
    }

    if ([type isEqualToString:@"collaborator"]) {
        if ([value isKindOfClass:[NSArray class]]) {
            NSArray *arr = (NSArray *)value;
            NSArray *users = relatedUsers[@"user_list"];
            NSMutableArray *cells = [NSMutableArray array];
            for (id email in arr) {
                NSDictionary *u = [self findUserByEmail:email users:users];
                if (u) {
                    NSDictionary *norm = [SeafSdocUserMapper normalizeUserDict:u];
                    NSString *name = norm[@"name"] ?: @"";
                    NSString *avatar = norm[@"avatarURL"] ?: @"";
                    [cells addObject:@{ @"user_name": name, @"avatar": avatar }];
                }
            }
            return cells;
        }
        return @[];
    }

    if ([type isEqualToString:@"single_select"]) {
        if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
            NSDictionary *opt = [self resolveOptionForValue:value fieldKey:key metadata:metadata metadataConfig:metadataConfig tagWrapper:tagWrapper];
            if (opt) {
                NSString *disp = opt[@"name"] ?: value;
                NSString *bg = opt[@"color"];
                NSString *tc = opt[@"textColor"];
                if ([key isEqualToString:@"_status"]) {
                    NSString *code = [value isKindOfClass:[NSString class]] ? (NSString *)value : @"";
                    // Localize the display name for status (server may return raw code like "_in_progress")
                    NSString *localizedDisp = NSLocalizedString(disp, nil);
                    if (localizedDisp.length > 0 && ![localizedDisp isEqualToString:disp]) {
                        disp = localizedDisp;
                    }
                    if (![bg isKindOfClass:[NSString class]] || bg.length == 0) {
                        NSDictionary *fallback = [self statusOptionForCode:code];
                        NSString *mapped = fallback[@"color"];
                        bg = (mapped.length > 0) ? mapped : @"#EED5FF";
                    }
                    if (![tc isKindOfClass:[NSString class]] || tc.length == 0) {
                        tc = @"#202428";
                    }
                    NSString *bgLower = [bg.lowercaseString copy];
                    if ([code isEqualToString:@"_done"] || [code isEqualToString:@"_outdated"] ||
                        [bgLower isEqualToString:@"#59cb74"] || [bgLower isEqualToString:@"#c2c2c2"]) {
                        tc = @"#FFFFFF";
                    }
                }
                return @[ @{ @"text": disp,
                             @"textColor": tc ?: @"",
                             @"color": bg ?: @"" } ];
            }
            if ([key isEqualToString:@"_status"]) {
                NSString *code = [value isKindOfClass:[NSString class]] ? (NSString *)value : @"";
                NSDictionary *fallback = [self statusOptionForCode:code];
                NSString *disp = fallback[@"name"] ?: (code.length ? code : @"");
                NSString *bg = fallback[@"color"] ?: @"#EED5FF";
                NSString *tc = fallback[@"textColor"] ?: @"#202428";
                return @[ @{ @"text": disp,
                             @"textColor": tc,
                             @"color": bg } ];
            }
            return @[ @{ @"text": value } ];
        }
        return @[];
    }

    if ([type isEqualToString:@"multiple_select"]) {
        if ([value isKindOfClass:[NSArray class]]) {
            NSMutableArray *cells = [NSMutableArray array];
            for (id v in (NSArray *)value) {
                NSString *valStr = [v isKindOfClass:[NSString class]] ? (NSString *)v : @"";
                NSDictionary *opt = [self resolveOptionForValue:valStr fieldKey:key metadata:metadata metadataConfig:metadataConfig tagWrapper:tagWrapper];
                if (opt) {
                    [cells addObject:@{ @"text": opt[@"name"] ?: (valStr ?: @""),
                                        @"textColor": opt[@"textColor"] ?: @"",
                                        @"color": opt[@"color"] ?: @"" }];
                } else {
                    [cells addObject:@{ @"text": valStr ?: @"" }];
                }
            }
            return cells;
        }
        return @[];
    }

    // Handle link type: specifically for _tags, resolve display from tagWrapper
    if ([type isEqualToString:@"link"]) {
        if ([key isEqualToString:@"_tags"]) {
            if ([value isKindOfClass:[NSArray class]]) {
                NSArray *links = (NSArray *)value; // each: { row_id, display_value }
                NSArray *tagResults = [tagWrapper isKindOfClass:[NSDictionary class]] ? tagWrapper[@"results"] : nil;
                NSMutableArray *cells = [NSMutableArray array];
                for (NSDictionary *link in links) {
                    NSString *rowId = link[@"row_id"] ?: link[@"id"];
                    NSDictionary *tag = nil;
                    if ([tagResults isKindOfClass:[NSArray class]]) {
                        for (NSDictionary *r in tagResults) {
                            NSString *rid = r[@"_id"] ?: r[@"id"]; // server uses _id
                            if ([rid isKindOfClass:[NSString class]] && [rid isEqualToString:rowId]) { tag = r; break; }
                        }
                    }
                    NSString *name = nil; NSString *color = nil;
                    if ([tag isKindOfClass:[NSDictionary class]]) {
                        name = tag[@"_tag_name"] ?: tag[@"name"] ?: link[@"display_value"];
                        color = tag[@"_tag_color"] ?: tag[@"color"];
                    } else {
                        name = link[@"display_value"] ?: @"";
                    }
                    if (name) {
                        [cells addObject:@{ @"text": name ?: @"",
                                            @"textColor": @"#202428",
                                            @"color": color ?: @"" }];
                    }
                }
                return cells;
            }
        }
        return @[];
    }

        if ([type isEqualToString:@"rate"]) {
        NSNumber *selected = [value isKindOfClass:[NSNumber class]] ? (NSNumber *)value : @(0);
        NSDictionary *cfg = [self firstConfigFromMetadata:metadata];
        NSNumber *max = nil; NSString *color = nil;
        if ([cfg isKindOfClass:[NSDictionary class]]) {
            max = cfg[@"max"] ?: cfg[@"rate_max_number"];
            color = cfg[@"color"] ?: cfg[@"rate_style_color"];
        }
        
        
        NSMutableDictionary *payload = [@{ @"ratingSelected": selected } mutableCopy];
        if (max) payload[@"ratingMax"] = max;
        if (color) payload[@"ratingColor"] = color;
        return @[ payload ];
    }

    if ([type isEqualToString:@"geolocation"]) {
        if ([value isKindOfClass:[NSDictionary class]]) {
            NSDictionary *cfg = [self firstConfigFromMetadata:metadata];
            NSString *geo = [cfg isKindOfClass:[NSDictionary class]] ? (cfg[@"geo_format"] ?: cfg[@"geoFormat"]) : nil;
            NSString *lat = value[@"lat"] ?: @"";
            NSString *lng = value[@"lng"] ?: @"";
            if (geo && [geo isKindOfClass:[NSString class]] && [geo isEqualToString:@"lng_lat"]) {
                if (lat.length && lng.length) return @[ @{ @"text": [NSString stringWithFormat:@"%@, %@", lat, lng] } ];
            }
            NSString *province = value[@"province"] ?: @"";
            NSString *city = value[@"city"] ?: @"";
            NSString *district = value[@"district"] ?: @"";
            NSString *detail = value[@"detail"] ?: @"";
            NSString *country_region = value[@"country_region"] ?: value[@"countryRegion"] ?: @"";
            if (country_region.length) return @[ @{ @"text": country_region } ];
            NSString *joined = [@[province, city, district, detail] componentsJoinedByString:@""];
            if (joined.length) return @[ @{ @"text": joined } ];
        }
        return @[];
    }

    if ([type isEqualToString:@"checkbox"]) {
        if ([value isKindOfClass:[NSNumber class]]) {
            return @[ @{ @"checked": value } ];
        }
        if ([value isKindOfClass:[NSString class]]) {
            BOOL b = [((NSString *)value) boolValue];
            return @[ @{ @"checked": @(b) } ];
        }
        return @[];
    }

    return @[];
}

#pragma mark - Date Formatting

+ (NSString *)formatDateValue:(id)value
{
    // Target format: yyyy-MM-dd HH:mm:ss (align with Android)
    if ([value isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)value;
        if (s.length == 0) return @"";

        // 1) Try ISO8601 with milliseconds / timezone, replace 'T' then parse
        NSString *norm = [s stringByReplacingOccurrencesOfString:@"T" withString:@" "];
        NSDate *date = nil;
        for (NSDateFormatter *parser in [self sharedParseDateFormatters]) {
            date = [parser dateFromString:norm];
            if (date) break;
        }
        if (!date) return norm; // fallback to normalized string
        return [[self sharedOutputDateFormatter] stringFromDate:date];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        // Treat as epoch seconds or milliseconds
        long long ts = [(NSNumber *)value longLongValue];
        if (ts > 100000000000) ts /= 1000; // ms -> s
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
        return [[self sharedOutputDateFormatter] stringFromDate:date];
    }
    return @"";
}

+ (NSDictionary *)findUserByEmail:(NSString *)email users:(NSArray *)users
{
    if (![email isKindOfClass:[NSString class]] || email.length == 0) return nil;
    for (NSDictionary *u in users) {
        NSString *em = u[@"email"] ?: u[@"contact_email"] ?: u[@"contactEmail"];
        if ([em isKindOfClass:[NSString class]] && [em isEqualToString:email]) {
            return u;
        }
    }
    return nil;
}

+ (NSDictionary *)findOptionByName:(NSString *)name inMetadata:(NSDictionary *)metadata tagWrapper:(NSDictionary *)tagWrapper
{
    // 1) Prefer options from metadata.data[0].options (Android behavior)
    id dataArr = metadata[@"data"] ?: metadata[@"configData"];
    if ([dataArr isKindOfClass:[NSArray class]] && [dataArr count] > 0) {
        NSDictionary *cfg = [dataArr firstObject];
        NSArray *opts = cfg[@"options"];
        if ([opts isKindOfClass:[NSArray class]]) {
            for (NSDictionary *o in opts) {
                NSString *n = o[@"name"];
                if ([n isKindOfClass:[NSString class]] && [n isEqualToString:name]) {
                    NSString *color = o[@"color"];
                    NSString *textColor = o[@"textColor"];
                    return @{ @"name": n ?: name, @"color": color ?: @"", @"textColor": textColor ?: @"" };
                }
            }
        }
    }
    // 1b) If metadata.data is a dictionary, try data.options
    if ([dataArr isKindOfClass:[NSDictionary class]]) {
        NSDictionary *cfg = (NSDictionary *)dataArr;
        NSArray *opts = cfg[@"options"];
        if ([opts isKindOfClass:[NSArray class]]) {
            for (NSDictionary *o in opts) {
                NSString *n = o[@"name"];
                if ([n isKindOfClass:[NSString class]] && [n isEqualToString:name]) {
                    NSString *color = o[@"color"];
                    NSString *textColor = o[@"textColor"];
                    return @{ @"name": n ?: name, @"color": color ?: @"", @"textColor": textColor ?: @"" };
                }
            }
        }
    }
    // 1c) Fallback: options directly under field (metadata)
    NSArray *fieldOpts = metadata[@"options"];
    if ([fieldOpts isKindOfClass:[NSArray class]]) {
        for (NSDictionary *o in fieldOpts) {
            NSString *n = o[@"name"];
            if ([n isKindOfClass:[NSString class]] && [n isEqualToString:name]) {
                NSString *color = o[@"color"];
                NSString *textColor = o[@"textColor"];
                return @{ @"name": n ?: name, @"color": color ?: @"", @"textColor": textColor ?: @"" };
            }
        }
    }
    return nil;
}

+ (NSDictionary *)firstConfigFromMetadata:(NSDictionary *)metadata
{
    id dataArr = metadata[@"data"] ?: metadata[@"configData"];
    if ([dataArr isKindOfClass:[NSArray class]] && [dataArr count] > 0) {
        id cfg = [dataArr firstObject];
        if ([cfg isKindOfClass:[NSDictionary class]]) return cfg;
    }
    // Support dictionary-shaped config: { color: ..., max: ..., ... }
    if ([dataArr isKindOfClass:[NSDictionary class]]) {
        return (NSDictionary *)dataArr;
    }
    return nil;
}

+ (NSString *)normalizeType:(NSString *)type key:(NSString *)key
{
    if (![type isKindOfClass:[NSString class]]) return @"text";
    NSString *t = [[type lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    t = [t stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    // Common aliases
    if ([t isEqualToString:@"long text"]) t = @"long_text";
    if ([t isEqualToString:@"single select"]) t = @"single_select";
    if ([t isEqualToString:@"multiple select"]) t = @"multiple_select";
    if ([t isEqualToString:@"geo"]) t = @"geolocation";
    if ([key isEqualToString:@"_file_modifier"]) return @"collaborator";
    return t;
}

+ (NSString *)readableSize:(long long)size
{
    //  base-1000, 0~1 decimal places (round half-up), and for size <= 0 return "0 KB"
    static NSArray *units; static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ units = @[ @"B", @"KB", @"MB", @"GB", @"TB" ]; });

    if (size <= 0) return @"0 KB";

    double s = (double)size; int idx = 0;
    while (s >= 1000.0 && idx < (int)units.count - 1) { s /= 1000.0; idx++; }

    NSNumberFormatter *fmt = [self sharedSizeNumberFormatter];
    NSString *numStr = [fmt stringFromNumber:@(s)];

    // For bytes, ensure no fractional part and show the raw integer bytes
    if (idx == 0) {
        numStr = [fmt stringFromNumber:@(size)];
    }

    return [NSString stringWithFormat:@"%@ %@", numStr, units[idx]];
}

#pragma mark - Option Resolve Fallback from metadataConfig

+ (NSDictionary *)findOptionByName:(NSString *)name inMetadataConfig:(NSDictionary *)metadataConfig forKey:(NSString *)key
{
    if (![metadataConfig isKindOfClass:[NSDictionary class]] || name.length == 0 || key.length == 0) return nil;
    // Possible containers where server may put field configs
    id c1 = [metadataConfig[@"fields"] isKindOfClass:[NSArray class]] ? metadataConfig[@"fields"] : @[];
    id c2 = [metadataConfig[@"metadata"] isKindOfClass:[NSArray class]] ? metadataConfig[@"metadata"] : @[];
    id c3 = [metadataConfig[@"columns"] isKindOfClass:[NSArray class]] ? metadataConfig[@"columns"] : @[];
    id c4 = [metadataConfig[@"items"] isKindOfClass:[NSArray class]] ? metadataConfig[@"items"] : @[];
    id c5 = [metadataConfig[@"data"] isKindOfClass:[NSArray class]] ? metadataConfig[@"data"] : @[];
    NSArray *containers = @[ c1, c2, c3, c4, c5 ];
    for (id cont in containers) {
        if (![cont isKindOfClass:[NSArray class]]) continue;
        for (NSDictionary *field in (NSArray *)cont) {
            if (![field isKindOfClass:[NSDictionary class]]) continue;
            NSString *k = field[@"key"] ?: field[@"name"];
            if (![k isKindOfClass:[NSString class]]) continue;
            if (![k isEqualToString:key]) continue;

            // Try options under typical paths
            NSArray *dataArr = field[@"data"] ?: field[@"configData"];
            if ([dataArr isKindOfClass:[NSArray class]] && dataArr.count > 0) {
                NSDictionary *cfg = [dataArr firstObject];
                NSArray *opts = cfg[@"options"] ?: field[@"options"];
                if ([opts isKindOfClass:[NSArray class]]) {
                    for (NSDictionary *o in opts) {
                        NSString *n = o[@"name"];
                        if ([n isKindOfClass:[NSString class]] && [n isEqualToString:name]) {
                            NSString *color = o[@"color"];
                            NSString *textColor = o[@"textColor"];
                            return @{ @"name": n ?: name,
                                      @"color": color ?: @"",
                                      @"textColor": textColor ?: @"" };
                        }
                    }
                }
            } else {
                // Direct options under field
                NSArray *opts = field[@"options"];
                if ([opts isKindOfClass:[NSArray class]]) {
                    for (NSDictionary *o in opts) {
                        NSString *n = o[@"name"];
                        if ([n isKindOfClass:[NSString class]] && [n isEqualToString:name]) {
                            NSString *color = o[@"color"];
                            NSString *textColor = o[@"textColor"];
                            return @{ @"name": n ?: name,
                                      @"color": color ?: @"",
                                      @"textColor": textColor ?: @"" };
                        }
                    }
                }
            }
        }
    }
    return nil;
}

+ (NSDictionary *)resolveOptionForValue:(NSString *)value fieldKey:(NSString *)key metadata:(NSDictionary *)metadata metadataConfig:(NSDictionary *)metadataConfig tagWrapper:(NSDictionary *)tagWrapper
{
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return nil;
    // 1) Try options from field metadata
    NSDictionary *opt = [self findOptionByName:value inMetadata:metadata tagWrapper:tagWrapper];
    if (opt) return opt;
    // 2) Try options scoped by field key from metadataConfig
    opt = [self findOptionByName:value inMetadataConfig:metadataConfig forKey:key ?: @""];
    if (opt) return opt;
    // 3) Try recursive search by field key anywhere in metadataConfig
    opt = [self findOptionByName:value inAnyObject:metadataConfig forFieldKey:key ?: @""];
    if (opt) return opt;
    // 4) Try recursive search anywhere ignoring field key
    opt = [self findOptionByNameAnywhere:value inAnyObject:metadataConfig];
    if (opt) return opt;
    return nil;
}

// Check whether an option dictionary matches a given value by multiple fields
+ (BOOL)option:(NSDictionary *)opt matchesValue:(NSString *)value
{
    if (![opt isKindOfClass:[NSDictionary class]] || ![value isKindOfClass:[NSString class]]) return NO;
    NSString *name = opt[@"name"];
    if ([name isKindOfClass:[NSString class]] && [name isEqualToString:value]) return YES;
    // Try id/value/code/key fields commonly used for code values
    NSArray *keys = @[ @"id", @"value", @"code", @"key" ];
    for (NSString *k in keys) {
        NSString *v = opt[k];
        if ([v isKindOfClass:[NSString class]] && [v isEqualToString:value]) return YES;
    }
    // Try localized display of the code to match name
    NSString *localizedValue = NSLocalizedString(value, nil);
    if ([localizedValue isKindOfClass:[NSString class]] && localizedValue.length > 0 && ![localizedValue isEqualToString:value]) {
        if ([name isKindOfClass:[NSString class]] && [name isEqualToString:localizedValue]) return YES;
    }
    return NO;
}

// Build a colored option for known _status codes as the last-resort fallback
+ (NSDictionary *)statusOptionForCode:(NSString *)code
{
    if (![code isKindOfClass:[NSString class]] || code.length == 0) return nil;
    // Android-aligned color mapping for _status
    static NSDictionary<NSString *, NSDictionary *> *map; static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"_outdated":    @{ @"name": NSLocalizedString(@"_outdated", nil) ?: @"_outdated",
                                  @"color": @"#C2C2C2",
                                  @"textColor": @"#FFFFFF" },
            @"_in_progress": @{ @"name": NSLocalizedString(@"_in_progress", nil) ?: @"_in_progress",
                                  @"color": @"#EED5FF",
                                  @"textColor": @"#202428" },
            @"_in_review":   @{ @"name": NSLocalizedString(@"_in_review", nil) ?: @"_in_review",
                                  @"color": @"#FFFDCD",
                                  @"textColor": @"#202428" },
            @"_done":        @{ @"name": NSLocalizedString(@"_done", nil) ?: @"_done",
                                  @"color": @"#59CB74",
                                  @"textColor": @"#FFFFFF" }
        };
    });
    NSDictionary *opt = map[code];
    if (opt) return opt;
    // If not one of the known codes, try using localized(code) with neutral text and no bg
    NSString *disp = NSLocalizedString(code, nil);
    if (disp.length == 0) disp = code;
    return @{ @"name": disp, @"color": @"", @"textColor": @"#202428" };
}

// Recursive search for option by name in arbitrary metadataConfig structure
+ (NSDictionary *)findOptionByName:(NSString *)name inAnyObject:(id)obj forFieldKey:(NSString *)fieldKey
{
    if (!obj) return nil;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)obj;
        NSString *dk = dict[@"key"] ?: dict[@"name"];
        BOOL isThisField = ([dk isKindOfClass:[NSString class]] && [dk isEqualToString:fieldKey]);
        if (isThisField) {
            // Try nested data/configData → options
            id dataArr = dict[@"data"] ?: dict[@"configData"];
            if ([dataArr isKindOfClass:[NSArray class]] && [dataArr count] > 0) {
                id cfg = [dataArr firstObject];
                if ([cfg isKindOfClass:[NSDictionary class]]) {
                    NSArray *opts = cfg[@"options"] ?: dict[@"options"];
                    if ([opts isKindOfClass:[NSArray class]]) {
                        for (NSDictionary *o in opts) {
                            if ([self option:o matchesValue:name]) {
                                NSString *n = o[@"name"] ?: name;
                                NSString *color = o[@"color"];
                                NSString *textColor = o[@"textColor"];
                                return @{ @"name": n,
                                          @"color": color ?: @"",
                                          @"textColor": textColor ?: @"" };
                            }
                        }
                    }
                }
            }
            // Try direct options at this level
            NSArray *opts = dict[@"options"];
            if ([opts isKindOfClass:[NSArray class]]) {
                for (NSDictionary *o in opts) {
                    if ([self option:o matchesValue:name]) {
                        NSString *n = o[@"name"] ?: name;
                        NSString *color = o[@"color"];
                        NSString *textColor = o[@"textColor"];
                        return @{ @"name": n,
                                  @"color": color ?: @"",
                                  @"textColor": textColor ?: @"" };
                    }
                }
            }
        }
        // Recurse into children
        for (id child in dict.allValues) {
            NSDictionary *res = [self findOptionByName:name inAnyObject:child forFieldKey:fieldKey];
            if (res) return res;
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        for (id child in (NSArray *)obj) {
            NSDictionary *res = [self findOptionByName:name inAnyObject:child forFieldKey:fieldKey];
            if (res) return res;
        }
    }
    return nil;
}

// Scan any 'options' arrays in the metadataConfig and try to match by name/id/value/code/key (ignoring field key)
+ (NSDictionary *)findOptionByNameAnywhere:(NSString *)value inAnyObject:(id)obj
{
    if (!obj || ![value isKindOfClass:[NSString class]]) return nil;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)obj;
        // direct options at this level
        NSArray *opts = dict[@"options"];
        if ([opts isKindOfClass:[NSArray class]]) {
            for (NSDictionary *o in opts) {
                if ([self option:o matchesValue:value]) {
                    NSString *n = o[@"name"] ?: value;
                    NSString *color = o[@"color"];
                    NSString *textColor = o[@"textColor"];
                    return @{ @"name": n,
                              @"color": color ?: @"",
                              @"textColor": textColor ?: @"" };
                }
            }
        }
        // options nested under data/configData
        id dataArr = dict[@"data"] ?: dict[@"configData"];
        if ([dataArr isKindOfClass:[NSArray class]] && [dataArr count] > 0) {
            id cfg = [dataArr firstObject];
            if ([cfg isKindOfClass:[NSDictionary class]]) {
                NSArray *opts2 = ((NSDictionary *)cfg)[@"options"];
                if ([opts2 isKindOfClass:[NSArray class]]) {
                    for (NSDictionary *o in opts2) {
                        if ([self option:o matchesValue:value]) {
                            NSString *n = o[@"name"] ?: value;
                            NSString *color = o[@"color"];
                            NSString *textColor = o[@"textColor"];
                            return @{ @"name": n,
                                      @"color": color ?: @"",
                                      @"textColor": textColor ?: @"" };
                        }
                    }
                }
            }
        }
        // recurse children
        for (id child in dict.allValues) {
            NSDictionary *res = [self findOptionByNameAnywhere:value inAnyObject:child];
            if (res) return res;
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        for (id child in (NSArray *)obj) {
            NSDictionary *res = [self findOptionByNameAnywhere:value inAnyObject:child];
            if (res) return res;
        }
    }
    return nil;
}

 
@end

