#import <Foundation/Foundation.h>
#import "SeafBase+Display.h"
#import "SeafRepos.h"
#import "SeafDir.h"
#import "SeafFile.h"
#import "FileSizeFormatter.h"

@implementation SeafBase (Display)

- (NSString *)displayDetailText {
    // Handle repository: size + formatted mtime
    if ([self isKindOfClass:[SeafRepo class]]) {
        SeafRepo *repo = (SeafRepo *)self;
        NSString *sizeStr = [FileSizeFormatter stringFromLongLong:repo.size];
        static NSDateFormatter *df = nil;
        if (!df) {
            df = [[NSDateFormatter alloc] init];
            df.dateFormat = @"yyyy-MM-dd";
        }
        NSString *dateStr = @"";
        if (repo.mtime > 0) {
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:repo.mtime];
            dateStr = [df stringFromDate:date];
        }
        if (sizeStr && dateStr.length > 0)
            return [NSString stringWithFormat:@"%@ • %@", sizeStr, dateStr];
        else if (sizeStr)
            return sizeStr;
        else
            return dateStr;
    }
    // Directory
    if ([self isKindOfClass:[SeafDir class]]) {
        return ((SeafDir *)self).detailText;
    }
    // File
    if ([self isKindOfClass:[SeafFile class]]) {
        return ((SeafFile *)self).detailText;
    }
    return @"";
}

@end 