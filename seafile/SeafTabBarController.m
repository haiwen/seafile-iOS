//
//  SeafTabBarController.m
//  seafile
//

#import "SeafTabBarController.h"
#import "SeafTabBarStyler.h"
#import "SeafTheme.h"

// Drawing titles outside UIKit's tab buttons avoids their monochrome vibrancy
// while leaving native title labels in place for layout and accessibility.
@interface SeafTabBarTitleView : UIView
@property (nonatomic, copy) NSArray<NSDictionary *> *titles;
@end

@implementation SeafTabBarTitleView
- (void)drawRect:(CGRect)rect
{
    for (NSDictionary *title in self.titles) {
        [title[@"text"] drawInRect:[title[@"frame"] CGRectValue]
                   withAttributes:title[@"attributes"]];
    }
}
@end

@interface SeafTabBar ()
@property (nonatomic, strong) SeafTabBarTitleView *seafTitleOverlay;
@end

@implementation SeafTabBar

- (void)layoutSubviews
{
    [super layoutSubviews];
    if (@available(iOS 26.0, *)) {
        NSMutableSet<NSString *> *titles = [NSMutableSet set];
        for (UITabBarItem *item in self.items) {
            if (item.title.length)
                [titles addObject:item.title];
        }
        NSMutableDictionary<NSString *, NSDictionary *> *drawnTitles = [NSMutableDictionary dictionary];
        NSMutableArray<UIView *> *views = [NSMutableArray arrayWithArray:self.subviews];
        for (NSUInteger index = 0; index < views.count; index++) {
            UIView *view = views[index];
            if (view == self.seafTitleOverlay)
                continue;
            [views addObjectsFromArray:view.subviews];
            if (![view isKindOfClass:UILabel.class])
                continue;
            UILabel *source = (UILabel *)view;
            if (![titles containsObject:source.text])
                continue;

            // The selection lens contains another copy of each title. Draw
            // each title once at its native position, above the glass material.
            CGRect frame = [source convertRect:source.bounds toView:self];
            if (!source.hidden && !CGRectIsEmpty(frame)) {
                // A suppressed system label can report its placeholder bounds.
                // Anchor stacked titles to the native icon and measure the
                // localized text with the system's current title font.
                for (UIView *sibling in source.superview.subviews) {
                    if (![sibling isKindOfClass:UIImageView.class] || !((UIImageView *)sibling).image)
                        continue;
                    CGRect icon = [sibling convertRect:sibling.bounds toView:self];
                    if (fabs(CGRectGetMidX(frame) - CGRectGetMidX(icon)) < CGRectGetWidth(icon)) {
                        CGSize size = [source.text sizeWithAttributes:@{NSFontAttributeName: source.font}];
                        frame.size = CGSizeMake(MIN(ceil(size.width), source.superview.bounds.size.width - 8), ceil(size.height));
                        // Keep the aligned title origin, with 1pt more space below the icon.
                        frame.origin = CGPointMake(CGRectGetMidX(icon) - frame.size.width / 2, ceil(CGRectGetMaxY(icon) + 2) + 1);
                    }
                    break;
                }
                NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
                paragraph.alignment = source.textAlignment;
                paragraph.lineBreakMode = source.lineBreakMode;
                UIColor *color = [source.text isEqualToString:self.selectedItem.title]
                    ? [SeafTheme accentOrange] : [SeafTheme secondaryText];
                drawnTitles[source.text] = @{
                    @"text": source.text,
                    @"frame": [NSValue valueWithCGRect:frame],
                    @"attributes": @{
                        NSFontAttributeName: source.font,
                        NSForegroundColorAttributeName: [color resolvedColorWithTraitCollection:self.traitCollection],
                        NSParagraphStyleAttributeName: paragraph,
                    },
                };
            }
            // Suppress native monochrome text without changing hit testing.
            if (!source.layer.mask)
                source.layer.mask = [CALayer layer];
        }
        if (!self.seafTitleOverlay) {
            self.seafTitleOverlay = [SeafTabBarTitleView new];
            self.seafTitleOverlay.backgroundColor = UIColor.clearColor;
            self.seafTitleOverlay.userInteractionEnabled = NO;
            self.seafTitleOverlay.isAccessibilityElement = NO;
            [self addSubview:self.seafTitleOverlay];
        }
        self.seafTitleOverlay.frame = self.bounds;
        NSArray *drawing = drawnTitles.allValues;
        if (![self.seafTitleOverlay.titles isEqualToArray:drawing]) {
            self.seafTitleOverlay.titles = drawing;
            [self.seafTitleOverlay setNeedsDisplay];
        }
        if (self.subviews.lastObject != self.seafTitleOverlay)
            [self bringSubviewToFront:self.seafTitleOverlay];
    }
}

@end

@interface SeafTabBarController ()
@property (nonatomic, copy) NSArray<UITabBarItem *> *coloredTabItems;
@property (nonatomic, strong) UIColor *unselectedIconColor;
@property (nonatomic, strong) NSMapTable<UITabBarItem *, UIImage *> *originalTabImages;
@property (nonatomic, strong) NSMapTable<UITabBarItem *, UIImage *> *originalSelectedTabImages;
@end

@implementation SeafTabBarController

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    BOOL translucent = [SeafTabBarStyler tabBarNeedsTranslucency:self.tabBar];
    [self updateTabImages];
    if (self.tabBar.translucent == translucent)
        return;
    self.tabBar.translucent = translucent;
    // Children size themselves against the bar on their next layout pass.
    [self.view setNeedsLayout];
    [self.selectedViewController.view setNeedsLayout];
}

- (void)updateTabImages
{
    if (@available(iOS 26.0, *)) {
        if (self.traitCollection.userInterfaceIdiom != UIUserInterfaceIdiomPhone)
            return;
        UIColor *color = [[SeafTheme secondaryText] resolvedColorWithTraitCollection:self.tabBar.traitCollection];
        NSArray<UITabBarItem *> *items = self.tabBar.items;
        if ([self.unselectedIconColor isEqual:color] &&
            [self.coloredTabItems isEqualToArray:items])
            return;

        if (!self.originalTabImages) {
            self.originalTabImages = [NSMapTable weakToStrongObjectsMapTable];
            self.originalSelectedTabImages = [NSMapTable weakToStrongObjectsMapTable];
        }
        for (UITabBarItem *item in items) {
            UIImage *original = [self.originalTabImages objectForKey:item];
            if (!original && item.image) {
                original = item.image;
                [self.originalTabImages setObject:original forKey:item];
                if (item.selectedImage)
                    [self.originalSelectedTabImages setObject:item.selectedImage forKey:item];
            }
            // Liquid Glass ignores normal iconColor and
            // unselectedItemTintColor for template images. Supply the
            // colors in both images, including the initially selected tab.
            UIImage *selected = [self.originalSelectedTabImages objectForKey:item] ?: original;
            item.selectedImage = [selected imageWithTintColor:[SeafTheme accentOrange] renderingMode:UIImageRenderingModeAlwaysOriginal];
            item.image = [original imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
        }
        self.unselectedIconColor = color;
        self.coloredTabItems = items;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self.view setNeedsLayout];
        [self.tabBar setNeedsLayout];
    }
}

@end
