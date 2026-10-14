//
//  SeafNavLeftItem.m
//  seafileApp
//
//  Created by henry on 2025/3/24.
//  Copyright © 2025 Seafile. All rights reserved.
//

#import "SeafNavLeftItem.h"
#import "SeafDir.h"
#import "SeafRepos.h" // Used to determine directory type
#import "SeafTheme.h"
#import "SeafNavigationBarStyler.h"
// Compiled into the SeafShare extension as well: no SeafAppDelegate, no
// UIApplication.sharedApplication here.

@interface SeafNavLeftItem ()
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, assign) CGFloat leftPadding;
@property (nonatomic, assign) CGFloat rightPadding;
@property (nonatomic, assign) CGFloat titleContentWidth;
- (BOOL)seaf_applyDisplayWidth:(CGFloat)totalWidth;
@end

@implementation SeafNavLeftItem

+ (instancetype)navLeftItemWithDirectory:(nullable SeafDir *)directory title:(nullable NSString *)title target:(id)target action:(SEL)action {
    // Create container with provisional width; will resize after measuring text
    SeafNavLeftItem *view = [[SeafNavLeftItem alloc] initWithFrame:CGRectMake(0, 0, 10, 44)];
    // The navigation bar sizes this view from its intrinsic width. Keep that
    // equal to the frame below so a long title cannot stretch the capsule.
    [view setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [view setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    BOOL needsBackButton = ((directory && ![directory isKindOfClass:[SeafRepos class]]) || title != nil);
    // 10pt leading inset + 10pt glyph + 20pt to the title. The 20pt gap is the
    // spacing this control had before the glyph moved in from the glass edge.
    view.leftPadding = needsBackButton ? 40.0f : 5.0f;
    // 10pt inside the custom view. Duo's glass adds about 6pt, so the title
    // sits ~16pt from the capsule's trailing edge, matching the leading inset.
    view.rightPadding = 10.0f;
    CGFloat leftPadding = view.leftPadding;

    if (needsBackButton) {
        // Fixed-size image view, not UIButton imageEdgeInsets. The button is
        // only the hit target; the glyph stays 10×20.
        UIButton *customButton = [UIButton buttonWithType:UIButtonTypeCustom];
        customButton.frame = CGRectMake(0, 0, leftPadding, 44);
        customButton.accessibilityLabel = NSLocalizedString(@"Back", @"Seafile");
        [customButton addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];

        UIImageView *icon = [[UIImageView alloc] initWithImage:[SeafNavigationBarStyler backArrowImage]];
        icon.tintColor = [SeafTheme galleryOperationText];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        // 10pt inside the custom view. Duo's glass adds about 5pt more, so the
        // glyph sits ~15pt from the capsule edge, matching the system symbol buttons.
        icon.frame = CGRectMake(10.0, (44.0 - 20.0) / 2.0, 10.0, 20.0);
        icon.userInteractionEnabled = NO;
        [customButton addSubview:icon];
        // The glass capsule wraps the chevron and the directory name. This
        // button grows to that whole capsule in layoutSubviews.
        customButton.isAccessibilityElement = NO;
        view.backButton = customButton;
        [view addSubview:customButton];
    }

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    view.titleLabel = titleLabel;
    titleLabel.text = title ?: directory.name;
    titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    titleLabel.textColor = [SeafTheme primaryText];
    titleLabel.numberOfLines = 1;
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    // Auto-fit: allow shrinking up to 2pt (20 -> 18)
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = (18.0f / 20.0f);
    titleLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    // The name sits in the back button. It must not keep the touch.
    titleLabel.userInteractionEnabled = NO;

    // Measure required width for the title text
    CGSize constraint = CGSizeMake(CGFLOAT_MAX, 44);
    CGRect textRect = [titleLabel.text boundingRectWithSize:constraint
                                                    options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                 attributes:@{NSFontAttributeName: titleLabel.font}
                                                    context:nil];

    view.titleContentWidth = ceil(textRect.size.width);
    if (view.backButton) {
        [view.backButton addSubview:titleLabel];
        view.isAccessibilityElement = YES;
        NSString *name = titleLabel.text;
        view.accessibilityLabel = name.length ? name : NSLocalizedString(@"Back", @"Seafile");
        view.accessibilityTraits = UIAccessibilityTraitButton | (name.length ? UIAccessibilityTraitHeader : (UIAccessibilityTraits)0);
    } else {
        [view addSubview:titleLabel];
    }

    UIView *targetView = [target isKindOfClass:[UIViewController class]] ? ((UIViewController *)target).viewIfLoaded : nil;
    CGFloat containerWidth = 0;
    UIEdgeInsets safeInsets = UIEdgeInsetsZero;
    if (targetView) {
        containerWidth = CGRectGetWidth(targetView.bounds);
        safeInsets = targetView.safeAreaInsets;
        if (containerWidth < 1.0 && targetView.window) {
            containerWidth = CGRectGetWidth(targetView.window.bounds);
        }
    }
    // Callers that know their trailing buttons pass a reserved width and
    // call this again after layout. 0 keeps the historical 70% cap.
    [view applyContainerWidth:containerWidth safeInsets:safeInsets reservedTrailingWidth:0];

    return view;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // The directory name shares this capsule. A tap on the name has to land
    // on the button, or it never calls the back action.
    self.backButton.frame = self.bounds;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (self.backButton && (hit == self || hit == self.titleLabel)) {
        return self.backButton;
    }
    return hit;
}

- (BOOL)accessibilityActivate {
    if (!self.backButton) {
        return [super accessibilityActivate];
    }
    [self.backButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    return YES;
}

- (CGSize)intrinsicContentSize {
    CGFloat width = CGRectGetWidth(self.bounds);
    if (width < 1.0) {
        return CGSizeMake(UIViewNoIntrinsicMetric, 44.0);
    }
    return CGSizeMake(width, 44.0);
}

- (BOOL)seaf_applyDisplayWidth:(CGFloat)totalWidth {
    if (fabs(CGRectGetWidth(self.bounds) - totalWidth) < 0.5) {
        self.backButton.frame = self.bounds;
        return NO;
    }
    CGRect frame = self.frame;
    frame.size.width = totalWidth;
    frame.size.height = 44.0;
    self.frame = frame;
    self.backButton.frame = self.bounds;
    self.titleLabel.frame = CGRectMake(self.leftPadding, 0, MAX(0.0, totalWidth - self.leftPadding - self.rightPadding), 44.0);
    [self invalidateIntrinsicContentSize];
    return YES;
}

- (BOOL)applyMaximumWidth:(CGFloat)maximumWidth {
    CGFloat minWidth = self.leftPadding + self.rightPadding;
    CGFloat maxAllowed = MAX(minWidth, maximumWidth);
    CGFloat totalWidth = MIN(self.leftPadding + self.titleContentWidth + self.rightPadding, maxAllowed);
    return [self seaf_applyDisplayWidth:totalWidth];
}

- (BOOL)applyContainerWidth:(CGFloat)containerWidth
                  safeInsets:(UIEdgeInsets)safeInsets
       reservedTrailingWidth:(CGFloat)reservedTrailingWidth
{
    if (containerWidth < 1.0) {
        // Callers that know their layout pass a width. Prefer the window this
        // item is in; the screen is only a last resort before the first layout.
        UIWindow *window = self.window;
        containerWidth = window ? CGRectGetWidth(window.bounds) : CGRectGetWidth([UIScreen mainScreen].bounds);
    }
    CGFloat safeWidth = containerWidth - safeInsets.left - safeInsets.right;
    if (safeWidth < 1.0) {
        safeWidth = containerWidth;
    }
    // 70% of the full window is the cap used on a normal iPhone. The safe-area
    // budget is what keeps the trailing "more" button out of Duo's status column.
    CGFloat ratioCap = MIN(containerWidth * 0.7, 600.0);
    CGFloat budget = safeWidth - MAX(0.0, reservedTrailingWidth);
    CGFloat maxAllowed = MIN(ratioCap, budget);
    CGFloat minWidth = self.leftPadding + self.rightPadding;
    if (maxAllowed < minWidth) {
        maxAllowed = MIN(minWidth, safeWidth);
    }
    CGFloat totalWidth = MIN(self.leftPadding + self.titleContentWidth + self.rightPadding, maxAllowed);
    return [self seaf_applyDisplayWidth:totalWidth];
}

@end
