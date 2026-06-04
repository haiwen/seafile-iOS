//
//  SeafActivityModel.m
//  Seafile
//
//  Created by three on 2019/6/12.
//

#import "SeafActivityModel.h"
#import "SeafDateFormatter.h"
#import "Constants.h"

@implementation SeafActivityModel

- (instancetype)initWithEventJSON:(NSDictionary *)event andOpsMap:(NSDictionary *)opsMap {
    if (self = [super init]) {
        // Parse basic information from the JSON event
        self.avatarURL = [NSURL URLWithString:[event objectForKey:@"avatar_url"]];
        self.authorName = [event objectForKey:@"author_name"];
        self.repoName = [event objectForKey:@"repo_name"];
        self.time = [SeafDateFormatter compareGMTTimeWithNow:[event objectForKey:@"time"]];
        
        // Additional parsing to determine the operation type and detail
        NSString *name = [event objectForKey:@"name"];
        NSString *opType = [event objectForKey:@"op_type"];
        NSString *objType = [event objectForKey:@"obj_type"];
        //For files ending with a (draft).md string, the front end identifies it as a draft file and replaces the original op_type field (file) with a draft
        if ([name hasSuffix:@"(draft).md"]) {
            objType = @"draft";
        }
        
        // Parse batch operation fields (server >= 14.0)
        // JSON null arrives as NSNull, which does not respond to integerValue
        id countObj = [event objectForKey:@"count"];
        self.count = [countObj respondsToSelector:@selector(integerValue)] ? [countObj integerValue] : 0;
        id detailsObj = [event objectForKey:@"details"];
        if ([detailsObj isKindOfClass:[NSArray class]]) {
            self.details = detailsObj;
        }
        
        // Get the operation description
        self.operation = [self getOperationFromOpType:opType objType:objType cleanUpTrashDays:[event objectForKey:@"days"]];
        self.attributedDetail = [self getAttributedDetail:event opType:opType objType:objType];
    }
    return self;
}

- (NSString *)getOperationFromOpType:(NSString *)opType objType:(NSString *)objType cleanUpTrashDays:(NSString *)days {
    if (!opType || !objType) {
        return @"";
    }

    // Handle clean-up-trash operation first
    if ([opType isEqualToString:@"clean-up-trash"]) {
        if ([days integerValue] > 0) {
            return [NSString stringWithFormat:NSLocalizedString(@"Removed items older than %@ days from trash", @"Seafile"), days];
        }
        return NSLocalizedString(@"Removed all items from trash", @"Seafile");
    }

    // Match Android's SystemSwitchUtils.obj_type() if-else structure
    if ([objType isEqualToString:@"repo"]) {
        if ([opType isEqualToString:@"create"]) {
            return NSLocalizedString(@"Created library", @"Seafile");
        } else if ([opType isEqualToString:@"rename"]) {
            return NSLocalizedString(@"Renamed library", @"Seafile");
        } else if ([opType isEqualToString:@"delete"]) {
            return NSLocalizedString(@"Deleted library", @"Seafile");
        } else if ([opType isEqualToString:@"restore"] || [opType isEqualToString:@"recover"]) {
            return NSLocalizedString(@"Restored library", @"Seafile");
        } else if ([opType isEqualToString:@"edit"]) {
            return NSLocalizedString(@"Updated library", @"Seafile");
        } else {
            return @"";
        }
    } else if ([objType isEqualToString:@"dir"]) {
        if ([opType isEqualToString:@"create"] || [opType isEqualToString:@"batch_create"]) {
            if (self.count > 1) {
                return [NSString stringWithFormat:NSLocalizedString(@"Created %ld folders", @"Seafile"), (long)self.count];
            }
            return NSLocalizedString(@"Created folder", @"Seafile");
        } else if ([opType isEqualToString:@"rename"]) {
            return NSLocalizedString(@"Renamed folder", @"Seafile");
        } else if ([opType isEqualToString:@"delete"] || [opType isEqualToString:@"batch_delete"]) {
            if (self.count > 1) {
                return [NSString stringWithFormat:NSLocalizedString(@"Deleted %ld folders", @"Seafile"), (long)self.count];
            }
            return NSLocalizedString(@"Deleted folder", @"Seafile");
        } else if ([opType isEqualToString:@"restore"] || [opType isEqualToString:@"recover"]) {
            return NSLocalizedString(@"Restored folder", @"Seafile");
        } else if ([opType isEqualToString:@"move"]) {
            return NSLocalizedString(@"Moved folder", @"Seafile");
        } else if ([opType isEqualToString:@"edit"]) {
            return NSLocalizedString(@"Updated folder", @"Seafile");
        } else {
            return @"";
        }
    } else if ([objType isEqualToString:@"file"]) {
        if ([opType isEqualToString:@"create"] || [opType isEqualToString:@"batch_create"]) {
            if (self.count > 1) {
                return [NSString stringWithFormat:NSLocalizedString(@"Created %ld files", @"Seafile"), (long)self.count];
            }
            return NSLocalizedString(@"Created file", @"Seafile");
        } else if ([opType isEqualToString:@"rename"]) {
            return NSLocalizedString(@"Renamed file", @"Seafile");
        } else if ([opType isEqualToString:@"delete"] || [opType isEqualToString:@"batch_delete"]) {
            if (self.count > 1) {
                return [NSString stringWithFormat:NSLocalizedString(@"Deleted %ld files", @"Seafile"), (long)self.count];
            }
            return NSLocalizedString(@"Deleted file", @"Seafile");
        } else if ([opType isEqualToString:@"restore"] || [opType isEqualToString:@"recover"]) {
            return NSLocalizedString(@"Restored file", @"Seafile");
        } else if ([opType isEqualToString:@"move"]) {
            return NSLocalizedString(@"Moved file", @"Seafile");
        } else if ([opType isEqualToString:@"update"] || [opType isEqualToString:@"edit"]) {
            return NSLocalizedString(@"Updated file", @"Seafile");
        } else {
            return @"";
        }
    } else if ([objType isEqualToString:@"draft"]) {
        if ([opType isEqualToString:@"create"]) {
            return NSLocalizedString(@"Created draft", @"Seafile");
        } else if ([opType isEqualToString:@"rename"]) {
            return NSLocalizedString(@"Renamed draft", @"Seafile");
        } else if ([opType isEqualToString:@"delete"]) {
            return NSLocalizedString(@"Deleted draft", @"Seafile");
        } else if ([opType isEqualToString:@"update"] || [opType isEqualToString:@"edit"]) {
            return NSLocalizedString(@"Updated draft", @"Seafile");
        } else if ([opType isEqualToString:@"publish"]) {
            return NSLocalizedString(@"Publish draft", @"Seafile");
        } else {
            return @"";
        }
    } else if ([objType isEqualToString:@"files"]) {
        if ([opType isEqualToString:@"create"]) {
            return NSLocalizedString(@"Created files", @"Seafile");
        } else {
            return @"";
        }
    } else {
        return @"";
    }
}

/// Build attributed detail string with dynamic coloring, aligned with Android ActivityAdapter.onBindActivity.
/// Colors: orange (BAR_COLOR_ORANGE) for active/clickable items, gray for deleted/secondary text.
- (NSAttributedString *)getAttributedDetail:(NSDictionary *)event opType:(NSString *)opType objType:(NSString *)objType {
    UIColor *grayColor = [UIColor grayColor];
    
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    
    if ([opType isEqualToString:@"rename"]) {
        // rename: oldName (gray) + " => " (gray) + newName (orange)
        NSString *oldName;
        NSString *newName;
        if ([objType isEqualToString:@"file"]) {
            oldName = [event objectForKey:@"old_name"] ?: @"";
            newName = [event objectForKey:@"name"] ?: @"";
        } else {
            NSString *old_key = [NSString stringWithFormat:@"old_%@_name", objType];
            NSString *key = [NSString stringWithFormat:@"%@_name", objType];
            oldName = [event objectForKey:old_key] ?: @"";
            newName = [event objectForKey:key] ?: @"";
        }
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:oldName attributes:@{NSForegroundColorAttributeName: grayColor}]];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" => " attributes:@{NSForegroundColorAttributeName: grayColor}]];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:newName attributes:@{NSForegroundColorAttributeName: BAR_COLOR_ORANGE}]];
        return result;
    }
    
    // Determine the primary name text
    NSString *name = [event objectForKey:@"name"] ?: @"";
    if ([opType isEqualToString:@"move"]) {
        name = [NSString stringWithFormat:@"%@ => %@", [event objectForKey:@"old_path"] ?: @"", [event objectForKey:@"path"] ?: @""];
    } else if ([opType isEqualToString:@"clean-up-trash"]) {
        name = [event objectForKey:@"repo_name"] ?: @"";
    }
    
    // Determine name color based on op_type (aligned with Android)
    BOOL isDelete = [opType isEqualToString:@"delete"] || [opType isEqualToString:@"batch_delete"];
    UIColor *nameColor = isDelete ? grayColor : BAR_COLOR_ORANGE;
    
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:name attributes:@{NSForegroundColorAttributeName: nameColor}]];
    
    // Append batch suffix with gray color ("and X other files/folders")
    if (self.details && self.details.count > 1) {
        NSInteger otherCount = self.count - 1;
        if (otherCount < 1) otherCount = 1;
        NSString *otherStr;
        if ([objType isEqualToString:@"dir"]) {
            otherStr = [NSString stringWithFormat:NSLocalizedString(@"and %ld other folders", @"Seafile"), (long)otherCount];
        } else {
            otherStr = [NSString stringWithFormat:NSLocalizedString(@"and %ld other files", @"Seafile"), (long)otherCount];
        }
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:@{NSForegroundColorAttributeName: grayColor}]];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:otherStr attributes:@{NSForegroundColorAttributeName: grayColor}]];
    }
    
    return result;
}

@end
