//
//  SeafActivityModel.m
//  Seafile
//
//  Created by three on 2019/6/12.
//

#import "SeafActivityModel.h"
#import "SeafDateFormatter.h"

@implementation SeafActivityModel

- (instancetype)initWithEventJSON:(NSDictionary *)event andOpsMap:(NSDictionary *)opsMap {
    if (self = [super init]) {
        self.avatarURL = [NSURL URLWithString:[event objectForKey:@"avatar_url"]];
        self.authorName = [event objectForKey:@"author_name"];
        self.repoName = [event objectForKey:@"repo_name"];
        self.time = [SeafDateFormatter compareGMTTimeWithNow:[event objectForKey:@"time"]];
        
        NSString *name = [event objectForKey:@"name"];
        NSString *opType = [event objectForKey:@"op_type"];
        NSString *objType = [event objectForKey:@"obj_type"];
        //For files ending with a (draft).md string, the front end identifies it as a draft file and replaces the original op_type field (file) with a draft
        if ([name hasSuffix:@"(draft).md"]) {
            objType = @"draft";
        }
        
        self.operation = [self getOpreationFromOpType:opType objType:objType opsMap:opsMap cleanUpTrashDays:[event objectForKey:@"days"]];
        self.detail = [self getDetail:event opType:opType objType:objType];
    }
    return self;
}

- (NSString *)getOpreationFromOpType:(NSString *)opType objType:(NSString *)objType opsMap:(NSDictionary *)opsMap cleanUpTrashDays:(NSString *)days {
    NSString *operation;
    if (opType && objType) {
        NSString *opsKey = [NSString stringWithFormat:@"%@ %@", opType, objType];
        operation = [opsMap objectForKey:opsKey];
        //clean-up-trash operation
        if ([opType isEqualToString:@"clean-up-trash"] && [days integerValue] > 0) {
            operation = [NSString stringWithFormat:NSLocalizedString(@"Removed items older than %@ days from trash", @"Seafile"), days];
        }
    }
    return operation;
}

- (NSString *)getDetail:(NSDictionary *)event opType:(NSString *)opType objType:(NSString *)objType {
    NSString *detail = [event objectForKey:@"name"];
    if ([opType isEqualToString:@"rename"]) {
        if ([objType isEqualToString:@"file"]) {
            detail = [NSString stringWithFormat:@"%@ => %@", [event objectForKey:@"old_name"], [event objectForKey:@"name"]];
        } else {
            NSString *old_key = [NSString stringWithFormat:@"old_%@_name", objType];
            NSString *key = [NSString stringWithFormat:@"%@_name", objType];
            detail = [NSString stringWithFormat:@"%@ => %@", [event objectForKey:old_key], [event objectForKey:key]];
        }
    } else if ([opType isEqualToString:@"move"]) {
        detail = [NSString stringWithFormat:@"%@ => %@", [event objectForKey:@"old_path"], [event objectForKey:@"path"]];
    } else if ([opType isEqualToString:@"clean-up-trash"]) {
        detail = [event objectForKey:@"repo_name"];
    }
    
    return detail;
}

@end
