//
//  SeafActivityModel.m
//  Seafile
//
//  Created by three on 2019/6/12.
//

#import "SeafActivityModel.h"
#import "SeafDateFormatter.h"

@implementation SeafActivityModel

- (instancetype)initWithNewAPIRequestJSON:(NSDictionary *)dict {
    if (self = [super init]) {
        self.avatar_url = [NSURL URLWithString:[dict objectForKey:@"avatar_url"]];
        self.author_name = [dict objectForKey:@"author_name"];
        self.repo_name = [dict objectForKey:@"repo_name"];
        self.time = [SeafDateFormatter compareCurrentFromGMTDate:[dict objectForKey:@"time"]];
        
        NSArray *keys = [NSArray arrayWithObjects:
                         @"create repo",
                         @"rename repo",
                         @"delete repo",
                         @"restore repo",
                         @"create dir",
                         @"rename dir",
                         @"delete dir",
                         @"restore dir",
                         @"move dir",
                         @"create file",
                         @"rename file",
                         @"delete file",
                         @"restore file",
                         @"move file",
                         @"edit file",
                         @"create draft",
                         @"delete draft",
                         @"edit draft",
                         @"publish draft",
                         @"create files",
                         nil];
        NSArray *values = [NSArray arrayWithObjects:
                           NSLocalizedString(@"Created library", @"Seafile"),
                           NSLocalizedString(@"Renamed library", @"Seafile"),
                           NSLocalizedString(@"Deleted library", @"Seafile"),
                           NSLocalizedString(@"Restored library", @"Seafile"),
                           NSLocalizedString(@"Created folder", @"Seafile"),
                           NSLocalizedString(@"Renamed folder", @"Seafile"),
                           NSLocalizedString(@"Deleted folder", @"Seafile"),
                           NSLocalizedString(@"Restored folder", @"Seafile"),
                           NSLocalizedString(@"Moved folder", @"Seafile"),
                           NSLocalizedString(@"Created file", @"Seafile"),
                           NSLocalizedString(@"Renamed file", @"Seafile"),
                           NSLocalizedString(@"Deleted file", @"Seafile"),
                           NSLocalizedString(@"Restored file", @"Seafile"),
                           NSLocalizedString(@"Moved file", @"Seafile"),
                           NSLocalizedString(@"Updated file", @"Seafile"),
                           NSLocalizedString(@"Created draft", @"Seafile"),
                           NSLocalizedString(@"Deleted draft", @"Seafile"),
                           NSLocalizedString(@"Updated draft", @"Seafile"),
                           NSLocalizedString(@"Publish draft", @"Seafile"),
                           NSLocalizedString(@"Created files", @"Seafile"),
                           nil];
        
        NSString *name = [dict objectForKey:@"name"];
        self.detail = name;
        if ([dict objectForKey:@"op_type"] && [dict objectForKey:@"obj_type"]) {
            NSString *op_type = [dict objectForKey:@"op_type"];
            NSString *obj_type = [dict objectForKey:@"obj_type"];
            if ([name containsString:@"(draft).md"]) {
                obj_type = @"draft";
            }
            
            NSString *opsKey = [NSString stringWithFormat:@"%@ %@", op_type, obj_type];
            NSDictionary *opsMap = [NSDictionary dictionaryWithObjects:values forKeys:keys];
            self.operation = [opsMap objectForKey:opsKey];
            
            if ([op_type isEqualToString:@"rename"]) {
                if ([obj_type isEqualToString:@"file"]) {
                    self.detail = [NSString stringWithFormat:@"%@ => %@", [dict objectForKey:@"old_name"], [dict objectForKey:@"name"]];
                } else {
                    NSString *old_key = [NSString stringWithFormat:@"old_%@_name", obj_type];
                    NSString *key = [NSString stringWithFormat:@"%@_name", obj_type];
                    self.detail = [NSString stringWithFormat:@"%@ => %@", [dict objectForKey:old_key], [dict objectForKey:key]];
                }
            } else if ([op_type isEqualToString:@"move"]) {
                self.detail = [NSString stringWithFormat:@"%@ => %@", [dict objectForKey:@"old_path"], [dict objectForKey:@"path"]];
            } else if ([op_type isEqualToString:@"clean-up-trash"]) {
                NSInteger days = [[dict objectForKey:@"days"] integerValue];
                if (days == 0) {
                    self.operation = NSLocalizedString(@"Removed all items from trash", @"Seafile");
                } else {
                    self.operation = [NSString stringWithFormat:NSLocalizedString(@"Removed items older than %ld days from trash", @"Seafile"), days];
                }
                self.detail = [dict objectForKey:@"repo_name"];
            }
        }
    }
    return self;
}

@end
