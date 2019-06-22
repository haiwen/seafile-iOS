//
//  SeafActivityModel.m
//  Seafile
//
//  Created by three on 2019/6/12.
//

#import "SeafActivityModel.h"
#import "SeafDateFormatter.h"

@implementation SeafActivityModel

- (instancetype)initWithEvenJSON:(NSDictionary *)even andOpsMap:(NSDictionary *)opsMap {
    if (self = [super init]) {
        self.avatarURL = [NSURL URLWithString:[even objectForKey:@"avatar_url"]];
        self.authorName = [even objectForKey:@"author_name"];
        self.repoName = [even objectForKey:@"repo_name"];
        self.time = [SeafDateFormatter compareGMTTimeWithNow:[even objectForKey:@"time"]];
        
        NSString *name = [even objectForKey:@"name"];
        NSString *opType = [even objectForKey:@"op_type"];
        NSString *objType = [even objectForKey:@"obj_type"];
        //For files ending with a (draft).md string, the front end identifies it as a draft file and replaces the original op_type field (file) with a draft
        if ([name hasSuffix:@"(draft).md"]) {
            objType = @"draft";
        }
        
        self.operation = [self getOpreationFromOpType:opType objType:objType opsMap:opsMap even:even];
        self.detail = [self eventRenamed:even opType:opType objType:objType];
    }
    return self;
}

- (NSString *)getOpreationFromOpType:(NSString *)opType objType:(NSString *)objType opsMap:(NSDictionary *)opsMap even:(NSDictionary *)even {
    NSString *operation;
    if (opType && objType) {
        NSString *opsKey = [NSString stringWithFormat:@"%@ %@", opType, objType];
        operation = [opsMap objectForKey:opsKey];
        //clean-up-trash operation
        if ([opType isEqualToString:@"clean-up-trash"]) {
            NSString *days = [even objectForKey:@"days"];
            if ([days integerValue] == 0) {
                operation = NSLocalizedString(@"Removed all items from trash", @"Seafile");
            } else {
                operation = [NSString stringWithFormat:NSLocalizedString(@"Removed items older than %@ days from trash", @"Seafile"), days];
            }
        }
    }
    return operation;
}

- (NSString *)eventRenamed:(NSDictionary *)even opType:(NSString *)opType objType:(NSString *)objType {
    NSString *detail = [even objectForKey:@"name"];
    if ([opType isEqualToString:@"rename"]) {
        if ([objType isEqualToString:@"file"]) {
            detail = [NSString stringWithFormat:@"%@ => %@", [even objectForKey:@"old_name"], [even objectForKey:@"name"]];
        } else {
            NSString *old_key = [NSString stringWithFormat:@"old_%@_name", objType];
            NSString *key = [NSString stringWithFormat:@"%@_name", objType];
            detail = [NSString stringWithFormat:@"%@ => %@", [even objectForKey:old_key], [even objectForKey:key]];
        }
    } else if ([opType isEqualToString:@"move"]) {
        detail = [NSString stringWithFormat:@"%@ => %@", [even objectForKey:@"old_path"], [even objectForKey:@"path"]];
    } else if ([opType isEqualToString:@"clean-up-trash"]) {
        detail = [even objectForKey:@"repo_name"];
    }
    
    return detail;
}

@end
