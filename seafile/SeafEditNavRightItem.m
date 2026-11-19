#import "SeafEditNavRightItem.h"

@implementation SeafEditNavRightItem
- (instancetype)initWithTitle:(NSString *)title imageName:(NSString *)imageName target:(id)target action:(SEL)action {
    self = [super initWithTitle:title style:UIBarButtonItemStylePlain target:target action:action];
    if (self) {
        self.tintColor = BAR_COLOR;
        self.accessibilityLabel = title;
        self.accessibilityIdentifier = @"directory_select_all_button";
    }
    return self;
}
@end
