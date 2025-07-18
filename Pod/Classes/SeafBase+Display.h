#import "SeafBase.h"

@interface SeafBase (Display)

/// Returns the text that should be shown in the cell subtitle for this entry (size + date for repo, or existing detailText for dir/file).
- (NSString *)displayDetailText;

@end 