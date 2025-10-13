//  SeafDocCommentCell.m

#import "SeafDocCommentCell.h"
#import "SeafDocCommentItem.h"
#import "SeafDocCommentContentItem.h"
#import "SeafConnection.h"
#import "Version.h"
#import "SeafDataTaskManager.h"
#import "SeafCacheManager.h"
#import <CommonCrypto/CommonDigest.h>

//  IMAGE_WIDTH = (SCREEN_WIDTH - 120dp) / 3
#define kImageWidth ((UIScreen.mainScreen.bounds.size.width - 120) / 3.0)

@interface SeafDocCommentCell ()

@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *resolvedLabel;
@property (nonatomic, strong) UIImageView *resolvedImageView;
@property (nonatomic, strong) UIButton *moreButton;

// Android-style: use a container layout instead of UITextView
@property (nonatomic, strong) UIView *contentContainer;
@property (nonatomic, strong) NSMutableArray<UIView *> *contentSubviews;
@property (nonatomic, strong) UITapGestureRecognizer *containerTap;

// Image tap callback
@property (nonatomic, copy) void(^onImageTapHandler)(NSString *imageURL);

// SeafConnection (reuse its authentication mechanism)
@property (nonatomic, weak) SeafConnection *connection;

// Grid layout parameters derived from container width
@property (nonatomic, assign) CGFloat gridImageSize;
@property (nonatomic, assign) CGFloat gridImageMargin; // equals 4pt per spec
@property (nonatomic, assign) NSInteger gridColumns;   // equals 3 per Android

// Track running image download tasks for cancellation on reuse/close
@property (nonatomic, strong) NSHashTable<NSURLSessionDataTask *> *runningImageTasks;
// Track running NSOperations created via SeafDataTaskManager
@property (nonatomic, strong) NSHashTable<NSOperation *> *runningOperations;

@end

@implementation SeafDocCommentCell
- (void)_computeGridParamsForContentWidth:(CGFloat)contentWidth
{
    self.gridImageMargin = 4.0;
    self.gridColumns = 3;
    CGFloat totalInterItem = self.gridImageMargin * 2 * self.gridColumns;
    CGFloat availableForImages = contentWidth - totalInterItem;
    self.gridImageSize = floor(availableForImages / self.gridColumns);
}


// Simple in-memory + disk cache for comment images
static NSCache *gCommentImageCache; // deprecated local cache, kept for backward compat but not used
static NSHashTable<NSURLSessionDataTask *> *gAllRunningImageTasks; // deprecated, kept for compat
static NSURLSession *gImageSession; // deprecated, kept for compat

+ (void)initialize
{
    if (self == [SeafDocCommentCell class]) {
        gCommentImageCache = [NSCache new];
        gCommentImageCache.countLimit = 200;
        // Rough 50MB cost limit to avoid unbounded growth
        gCommentImageCache.totalCostLimit = 50 * 1024 * 1024;
        gAllRunningImageTasks = [NSHashTable weakObjectsHashTable];
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 15.0;
        cfg.timeoutIntervalForResource = 30.0;
        cfg.HTTPMaximumConnectionsPerHost = 6;
        gImageSession = [NSURLSession sessionWithConfiguration:cfg];

        // Memory pressure handling
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_onMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
}

+ (void)_onMemoryWarning:(NSNotification *)n
{
    [gCommentImageCache removeAllObjects];
}
- (void)dealloc
{
    [self cancelLoading];
}

// Cancel all comment image downloads (class method)
+ (void)cancelAllImageLoads
{
    for (NSURLSessionDataTask *task in gAllRunningImageTasks) {
        if (task && task.state == NSURLSessionTaskStateRunning) {
            [task cancel];
        }
    }
    [gAllRunningImageTasks removeAllObjects];
}

// SHA1 for stable filename
static NSString *sha1String(NSString *s)
{
    if (!s) return @"";
    const char *cstr = [s UTF8String];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(cstr, (CC_LONG)strlen(cstr), digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [out appendFormat:@"%02x", digest[i]];
    }
    return out;
}

static NSString *commentImageCacheDir()
{
    static NSString *dir;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *base = (paths.count > 0) ? paths.firstObject : NSTemporaryDirectory();
        dir = [base stringByAppendingPathComponent:@"SeafCommentImageCache"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return dir;
}

- (UIImage *)_cachedImageForURL:(NSString *)url
{
    // Use SeafCacheManager's URL image cache
    return [[SeafCacheManager sharedManager] getImageForURL:url];
}

- (void)_storeImage:(UIImage *)img forURL:(NSString *)url
{
    [[SeafCacheManager sharedManager] storeImage:img forURL:url];
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _runningImageTasks = [NSHashTable weakObjectsHashTable];
        _runningOperations = [NSHashTable weakObjectsHashTable];

        _avatarView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _avatarView.layer.cornerRadius = 16.0;
        _avatarView.layer.masksToBounds = YES;
        _avatarView.contentMode = UIViewContentModeScaleAspectFill;
        [self.contentView addSubview:_avatarView];

        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _nameLabel.textColor = [UIColor labelColor];
        [self.contentView addSubview:_nameLabel];

        _timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _timeLabel.font = [UIFont systemFontOfSize:12];
        _timeLabel.textColor = [UIColor secondaryLabelColor];
        [self.contentView addSubview:_timeLabel];

        _resolvedLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _resolvedLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _resolvedLabel.textColor = [UIColor systemGreenColor];
        _resolvedLabel.text = NSLocalizedString(@"Resolved", nil);
        _resolvedLabel.hidden = YES;
        [self.contentView addSubview:_resolvedLabel];

        // Android-style Resolved icon (12dp)
        _resolvedImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _resolvedImageView.contentMode = UIViewContentModeScaleAspectFit;
        if (@available(iOS 13.0, *)) {
            _resolvedImageView.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
            _resolvedImageView.tintColor = [UIColor systemGreenColor];
        }
        _resolvedImageView.hidden = YES;
        [self.contentView addSubview:_resolvedImageView];

        // Android-style: use a container layout (akin to FlexboxLayout)
        _contentContainer = [[UIView alloc] initWithFrame:CGRectZero];
        _contentContainer.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_contentContainer];
        // Single container-level gesture to avoid per-image gesture accumulation
        _containerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onContainerTapped:)];
        [_contentContainer addGestureRecognizer:_containerTap];
        
        // 32dp × 32dp more button (added last to ensure topmost)
        _moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
        // Prefer the same "more" asset as the file view
        UIImage *moreAsset = [UIImage imageNamed:@"more"];
        UIImage *moreIcon = nil;
        if (moreAsset) {
            moreIcon = moreAsset;
        } else if (@available(iOS 13.0, *)) {
            moreIcon = [UIImage systemImageNamed:@"ellipsis.vertical"];
        }
        if (moreIcon) {
            // Keep consistent size and legibility
            if (@available(iOS 13.0, *)) {
                UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightRegular];
                UIImage *sym = [moreIcon imageByApplyingSymbolConfiguration:cfg];
                [_moreButton setImage:(sym ?: moreIcon) forState:UIControlStateNormal];
            } else {
                [_moreButton setImage:moreIcon forState:UIControlStateNormal];
            }
        } else {
            [_moreButton setTitle:@"⋮" forState:UIControlStateNormal];
            _moreButton.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
            if (@available(iOS 13.0, *)) {
                [_moreButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
            } else {
                [_moreButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
            }
        }
        if (@available(iOS 13.0, *)) {
            _moreButton.tintColor = [UIColor secondaryLabelColor]; // Slightly darker for better visibility
        } else {
            _moreButton.tintColor = [UIColor colorWithWhite:0.2 alpha:1.0];
        }
        _moreButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        _moreButton.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        [self.contentView addSubview:_moreButton];
        
        _contentSubviews = [NSMutableArray array];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    // paddingVertical="8dp", paddingHorizontal="16dp"
    UIEdgeInsets insets = UIEdgeInsetsMake(8, 16, 8, 16);
    CGFloat width = self.contentView.bounds.size.width;

    // 32dp × 32dp avatar
    self.avatarView.frame = CGRectMake(insets.left, insets.top, 32, 32);
    
    // layout_marginStart="8dp" (avatar right margin)
    CGFloat rightStart = CGRectGetMaxX(self.avatarView.frame) + 8.0;
    CGFloat rightWidth = width - rightStart - insets.right;

    // Align with nav-bar "more" visuals: slightly smaller (near 24pt target) but keep 32pt container
    CGFloat iconBox = 32.0;
    CGFloat iconSize = 20.0;
    CGFloat bx = self.contentView.bounds.size.width - insets.right - iconBox;
    CGFloat by = insets.top;
    self.moreButton.frame = CGRectMake(bx, by, iconBox, iconBox);
    self.moreButton.imageEdgeInsets = UIEdgeInsetsMake((iconBox - iconSize)/2.0, (iconBox - iconSize)/2.0, (iconBox - iconSize)/2.0, (iconBox - iconSize)/2.0);

    CGSize nameSize = [self.nameLabel sizeThatFits:CGSizeMake(rightWidth - 36, 20)];
    self.nameLabel.frame = CGRectMake(rightStart, insets.top, MIN(rightWidth - 36, nameSize.width), 18);

    // layout_marginTop="4dp" (spacing from name to time)
    CGSize timeSize = [self.timeLabel sizeThatFits:CGSizeMake(rightWidth, 16)];
    self.timeLabel.frame = CGRectMake(rightStart, CGRectGetMaxY(self.nameLabel.frame) + 4, MIN(rightWidth, timeSize.width), 16);

    // Keep text label (backward compatibility)
    self.resolvedLabel.frame = CGRectMake(CGRectGetMaxX(self.timeLabel.frame) + 4, CGRectGetMinY(self.timeLabel.frame), 60, 16);
    
    // Make the Resolved icon 16dp; same height as time text and vertically aligned
    self.resolvedImageView.frame = CGRectMake(CGRectGetMaxX(self.timeLabel.frame) + 4, CGRectGetMinY(self.timeLabel.frame), 16, 16);

    // layout_marginTop="4dp" (content area top margin)
    CGFloat contentTop = MAX(CGRectGetMaxY(self.avatarView.frame), CGRectGetMaxY(self.timeLabel.frame)) + 4;
    
    // FlexboxLayout layout_width="match_parent": start from left margin, not from right of avatar
    // LinearLayout already has paddingHorizontal="16dp", so FlexboxLayout starts from the left margin
    CGFloat contentLeft = insets.left;
    CGFloat contentWidth = width - insets.left - insets.right;
    
    // Precompute grid parameters based on available width to avoid rounding drift
    [self _computeGridParamsForContentWidth:contentWidth];

    // Android-style: layout subviews in the container (FlexboxLayout with flex-wrap): text takes a full row, images use a grid
    CGFloat yOffset = 0;
    CGFloat xOffset = 0;
    CGFloat rowHeight = 0;
    
    NSUInteger index = 0;
    for (UIView *subview in self.contentSubviews) {
        CGSize subSize = subview.bounds.size;
        
        // Text view (UIView wrapping UILabel/UITextView) or image view (UIImageView)
        UIView *inner = subview.subviews.firstObject;
        BOOL isTextView = ([inner isKindOfClass:[UILabel class]] || [inner isKindOfClass:[UITextView class]]);
        BOOL isImageView = [subview isKindOfClass:[UIImageView class]];
        
        // If it's a text view, occupy a full row
        if (isTextView) {
            // If the previous row has pending image row height, wrap first
            if (rowHeight > 0) {
                yOffset += rowHeight;
                xOffset = 0;
                rowHeight = 0;
            }
            // textView.setPadding(DP_4, DP_8, DP_4, DP_8) - left/right 4dp, top/bottom 8dp
            // The UIView wrapper contains Label/TextView; padding is handled there
            subview.frame = CGRectMake(0, yOffset, contentWidth, subSize.height);
            yOffset += subSize.height;
            xOffset = 0;
            rowHeight = 0;
        }
        // If it's an image, arrange in rows
        else if (isImageView) {
            CGFloat imageMargin = self.gridImageMargin;
            CGFloat imageWidth = self.gridImageSize;
            CGFloat imageHeight = self.gridImageSize; // square grid

            CGFloat imageWithMargin = imageWidth + imageMargin * 2;

            // Wrap decision (consider margins)
            if (xOffset + imageWithMargin > contentWidth && xOffset > 0) {
                yOffset += rowHeight;
                xOffset = 0;
                rowHeight = 0;
            }

            // Fix image to a square grid size to avoid overflow in mixed layout
            subview.frame = CGRectMake(xOffset + imageMargin, yOffset + imageMargin, imageWidth, imageHeight);
            xOffset += imageWithMargin;
            rowHeight = MAX(rowHeight, imageHeight + imageMargin * 2);
        }

        
        index++;
    }
    
    if (rowHeight > 0) yOffset += rowHeight;
    if (yOffset == 0 && self.contentSubviews.count > 0) yOffset = 20; // ensure minimal height
    
    // FlexboxLayout starts at the left margin, not to the right of the avatar
    self.contentContainer.frame = CGRectMake(contentLeft, contentTop, contentWidth, yOffset);

    // Ensure the more button stays on top so later subviews don't cover it
    [self.contentView bringSubviewToFront:self.moreButton];
}

- (CGSize)sizeThatFits:(CGSize)size
{
    // paddingVertical="8dp", paddingHorizontal="16dp"
    UIEdgeInsets insets = UIEdgeInsetsMake(8, 16, 8, 16);
    CGFloat width = size.width;
    
    // FlexboxLayout layout_width="match_parent": width = parent width - horizontal padding
    CGFloat contentWidth = width - insets.left - insets.right;

    // 1) Avatar section height (from top)
    CGFloat avatarSectionHeight = insets.top + 32; // avatar height 32pt
    
    // 2) Name + time section height (from top)
    CGFloat headerSectionHeight = insets.top + 18 + 4 + 16; // name(18) + margin(4) + time(16)
    
    // Take the larger value as the total header height
    CGFloat headerHeight = MAX(avatarSectionHeight, headerSectionHeight);

    // 3) Compute content area height
    CGFloat contentHeight = 0;
    // Use same grid parameters as layoutSubviews to keep measurement and layout in sync
    [self _computeGridParamsForContentWidth:contentWidth];
    if (self.contentSubviews.count > 0) {

        CGFloat yOffset = 0;
        CGFloat xOffset = 0;
        CGFloat rowHeight = 0;
        
    for (UIView *subview in self.contentSubviews) {
        CGSize subSize = subview.bounds.size;
        
        // Text view (UIView wrapping UILabel/UITextView) or image view (UIImageView)
        UIView *inner = subview.subviews.firstObject;
        BOOL isTextView = ([inner isKindOfClass:[UILabel class]] || [inner isKindOfClass:[UITextView class]]);
        BOOL isImageView = [subview isKindOfClass:[UIImageView class]];
            
            if (isTextView) {
                if (rowHeight > 0) {
                    yOffset += rowHeight;
                    xOffset = 0;
                    rowHeight = 0;
                }
                yOffset += subSize.height;
                xOffset = 0;
                rowHeight = 0;
            }
            else if (isImageView) {
                CGFloat imageMargin = self.gridImageMargin;
                CGFloat imageWidth = self.gridImageSize;
                CGFloat imageHeight = self.gridImageSize;
                CGFloat imageWithMargin = imageWidth + imageMargin * 2;

                if (xOffset + imageWithMargin > contentWidth && xOffset > 0) {
                    yOffset += rowHeight;
                    xOffset = 0;
                    rowHeight = 0;
                }
                xOffset += imageWithMargin;
                rowHeight = MAX(rowHeight, imageHeight + imageMargin * 2);
            }
        }
        
        // Add the last row height
        if (rowHeight > 0) yOffset += rowHeight;
        
        contentHeight = yOffset;
    }
    
    // 4) Total height = header + content top margin (4pt) + content height + bottom padding
    CGFloat totalHeight = headerHeight + 4 + contentHeight + insets.bottom;
    
    
    
    return CGSizeMake(size.width, totalHeight);
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [self cancelLoading];
    // Remove all gestures added previously to avoid stacking
    for (UIGestureRecognizer *gr in self.contentView.gestureRecognizers.copy) {
        [self.contentView removeGestureRecognizer:gr];
    }
    self.avatarView.image = nil;
    self.nameLabel.text = @"";
    self.timeLabel.text = @"";
    self.resolvedLabel.hidden = YES;
    self.resolvedImageView.hidden = YES;
    
    // Clear all content subviews
    for (UIView *subview in self.contentSubviews) {
        [subview removeFromSuperview];
    }
    [self.contentSubviews removeAllObjects];
}

- (void)cancelLoading
{
    for (NSURLSessionDataTask *task in self.runningImageTasks) {
        if (task && (task.state == NSURLSessionTaskStateRunning || task.state == NSURLSessionTaskStateSuspended)) {
            [task cancel];
        }
    }
    [self.runningImageTasks removeAllObjects];
    for (NSOperation *op in self.runningOperations) {
        if (op && !op.isCancelled && !op.isFinished) {
            [op cancel];
        }
    }
    [self.runningOperations removeAllObjects];
}

- (void)configureWithItem:(SeafDocCommentItem *)item
{
    [self configureWithItem:item connection:nil];
}

- (void)configureWithItem:(SeafDocCommentItem *)item connection:(SeafConnection *)connection
{
    // Store connection (for authenticated image loading)
    self.connection = connection;
    // Any previous tasks must be cancelled before reconfiguring
    [self cancelLoading];
    
    // Clear previous content subviews first (important for sizing cell)
    for (UIView *subview in self.contentSubviews) {
        [subview removeFromSuperview];
    }
    [self.contentSubviews removeAllObjects];
    
    self.nameLabel.text = item.author;
    self.timeLabel.text = item.timeString;
    
    // Set background color according to resolved state
    if (item.resolved) {
        // comment_resolved_color = material_grey_50 = #FAFAFA
        self.contentView.backgroundColor = [UIColor colorWithRed:250.0/255.0 green:250.0/255.0 blue:250.0/255.0 alpha:1.0];
        
        // Prefer using the icon
        if (@available(iOS 13.0, *)) {
            self.resolvedImageView.hidden = NO;
            self.resolvedLabel.hidden = YES;
        } else {
            self.resolvedImageView.hidden = YES;
            self.resolvedLabel.hidden = NO;
        }
    } else {
        // window_background_color = material_grey_100 = #F5F5F5
        self.contentView.backgroundColor = [UIColor colorWithRed:245.0/255.0 green:245.0/255.0 blue:245.0/255.0 alpha:1.0];
        
        // Hide resolved indicator
        self.resolvedImageView.hidden = YES;
        self.resolvedLabel.hidden = YES;
    }
    
    // Load avatar using a default placeholder; route via SeafDataTaskManager (auth/cancellable/shared queue)
    UIImage *placeholderAvatar = [UIImage imageNamed:@"account"];
    self.avatarView.image = placeholderAvatar;
    if (item.avatarURL.length > 0) {
        UIImage *cachedAvatar = [self _cachedImageForURL:item.avatarURL];
        if (cachedAvatar) {
            self.avatarView.image = cachedAvatar;
        } else if (self.connection) {
            __weak typeof(self) wself = self;
            NSOperation *op = [SeafDataTaskManager.sharedObject addCommentImageDownload:item.avatarURL
                                                                             connection:self.connection
                                                                             completion:^(UIImage * _Nullable image, NSString * _Nonnull urlStr) {
                __strong typeof(wself) sself = wself; if (!sself) return;
                if (image) {
                    sself.avatarView.image = image;
                    [sself _storeImage:image forURL:urlStr];
                }
            }];
            if (op) [self.runningOperations addObject:op];
        }
    }
    
    // Android-style: dynamically create text and image views from contentItems
    if (item.contentItems && item.contentItems.count > 0) {
        [self buildContentViewsWithItems:item.contentItems];
    } else if (item.attributedContent) {
        // Backward compatibility: if no contentItems, use attributedContent (legacy)
        NSString *plainText = item.attributedContent.string ?: @"";
        if (plainText.length > 0) {
            // FlexboxLayout layout_width="match_parent"
            CGFloat containerWidth = self.contentView.bounds.size.width - 16 - 16;  // paddingHorizontal="16dp"
            if (containerWidth <= 0) containerWidth = UIScreen.mainScreen.bounds.size.width - 16 - 16;
            [self appendTextToContainer:plainText containerWidth:containerWidth];
        }
    }
}

// Android-style: build content views (akin to Android's addViews)
- (void)buildContentViewsWithItems:(NSArray<SeafDocCommentContentItem *> *)contentItems
{
    // FlexboxLayout layout_width="match_parent": width = parent width - horizontal padding
    // Compute container width; if bounds are not set yet, use screen width as a reference
    CGFloat containerWidth = self.contentView.bounds.size.width - 16 - 16;  // paddingHorizontal="16dp"
    if (containerWidth <= 0) {
        // For the first layout, estimate using screen width
        containerWidth = UIScreen.mainScreen.bounds.size.width - 16 - 16;
    }
    
    NSUInteger i = 0;
    for (SeafDocCommentContentItem *contentItem in contentItems) {
        if (contentItem.type == SeafDocCommentContentTypeText) {
            // appendMovementTextToFlex
            [self appendTextToContainer:contentItem.content containerWidth:containerWidth];
        } else if (contentItem.type == SeafDocCommentContentTypeImage) {
            // appendImageToFlex
            [self appendImageToContainer:contentItem.content];
        }
        
        i++;
    }
    
    [self setNeedsLayout];
}

// appendMovementTextToFlex
- (void)appendTextToContainer:(NSString *)text containerWidth:(CGFloat)width
{
    if (text.length == 0) return;
    
    // Wrap UITextView in a UIView to mirror Android padding and full-row behavior
    UIView *paddingView = [[UIView alloc] initWithFrame:CGRectZero];
    paddingView.backgroundColor = [UIColor clearColor];
    
    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectZero];
    textView.editable = NO;
    textView.scrollEnabled = NO;
    textView.selectable = YES;
    textView.backgroundColor = [UIColor clearColor];
    textView.textContainerInset = UIEdgeInsetsMake(8, 4, 8, 4); // top/bottom 8, left/right 4
    textView.textContainer.lineFragmentPadding = 0; // remove extra internal left/right padding
    
    // Base text style
    NSDictionary *baseAttrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:14],
                                 NSForegroundColorAttributeName: [UIColor colorWithRed:0x21/255.0 green:0x25/255.0 blue:0x29/255.0 alpha:1.0] };
    
    // Lightweight Markdown link parsing: convert [text](url) to clickable links
    NSAttributedString *attr = [self attributedStringByParsingMarkdownLinks:text baseAttributes:baseAttrs];
    if (attr.length > 0) {
        textView.attributedText = attr;
    } else {
        textView.attributedText = [[NSAttributedString alloc] initWithString:text attributes:baseAttrs];
    }
    textView.dataDetectorTypes = UIDataDetectorTypeLink; // also enable detection of plain URLs
    
    // Compute height based on container width
    // Use "width" (outer container width) so the text view's padding applies within the width
    CGSize fit = [textView sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    CGFloat tvH = ceil(fit.height);
    // Minimum height to match Android single line (~20 text + 8+8 padding)
    tvH = MAX(tvH, 20 + 8 + 8);
    textView.frame = CGRectMake(0, 0, width, tvH);
    
    paddingView.bounds = CGRectMake(0, 0, width, tvH);
    [paddingView addSubview:textView];
    [self.contentContainer addSubview:paddingView];
    [self.contentSubviews addObject:paddingView];
}

// Parse [text](url) into an attributed string with NSLinkAttributeName, preserving the base text style
- (NSAttributedString *)attributedStringByParsingMarkdownLinks:(NSString *)text baseAttributes:(NSDictionary<NSAttributedStringKey, id> *)baseAttrs
{
    if (text.length == 0) return [[NSAttributedString alloc] initWithString:@"" attributes:baseAttrs];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSError *err = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\[([^\\]]+)\\]\\(([^\\)]+)\\)" options:0 error:&err];
    if (err) {
        return [[NSAttributedString alloc] initWithString:text attributes:baseAttrs];
    }
    __block NSUInteger cursor = 0;
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *m in matches) {
        if (m.range.location > cursor) {
            NSString *plain = [text substringWithRange:NSMakeRange(cursor, m.range.location - cursor)];
            if (plain.length > 0) {
                [result appendAttributedString:[[NSAttributedString alloc] initWithString:plain attributes:baseAttrs]];
            }
        }
        NSString *title = @"";
        NSString *urlStr = @"";
        if (m.numberOfRanges >= 3) {
            title = [text substringWithRange:[m rangeAtIndex:1]] ?: @"";
            urlStr = [text substringWithRange:[m rangeAtIndex:2]] ?: @"";
        }
        if (title.length > 0) {
            NSMutableDictionary *linkAttrs = [baseAttrs mutableCopy];
            if (urlStr.length > 0) {
                linkAttrs[NSLinkAttributeName] = urlStr;
            }
            NSAttributedString *linkStr = [[NSAttributedString alloc] initWithString:title attributes:linkAttrs];
            [result appendAttributedString:linkStr];
        }
        cursor = m.range.location + m.range.length;
    }
    if (cursor < text.length) {
        NSString *tail = [text substringFromIndex:cursor];
        if (tail.length > 0) {
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:tail attributes:baseAttrs]];
        }
    }
    return result.copy;
}

//  appendImageToFlex
- (void)appendImageToContainer:(NSString *)imageURL
{
    if (imageURL.length == 0) return;
    
    // IMAGE_WIDTH = (SCREEN_WIDTH - 120dp) / 3
    CGFloat imageSize = kImageWidth;
    
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    imageView.layer.cornerRadius = 4.0; // ShapeCorner4Style
    imageView.bounds = CGRectMake(0, 0, imageSize, imageSize);
    imageView.userInteractionEnabled = YES;
    imageView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0]; // placeholder background
    
    // Use SeafDataTaskManager's thumb queue to download (reachability/pause-resume/batch cancel)
    if (imageURL.length > 0) {
        UIImage *cached = [self _cachedImageForURL:imageURL];
        if (cached) {
            imageView.image = cached;
        }
        __weak typeof(imageView) wImageView = imageView;
        __weak typeof(self) wself = self;
        NSOperation *op = [SeafDataTaskManager.sharedObject addCommentImageDownload:imageURL connection:self.connection completion:^(UIImage * _Nullable image, NSString * _Nonnull urlStr) {
            if (!image) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                UIImageView *strongImgView = wImageView;
                if (strongImgView) strongImgView.image = image;
            });
            __strong typeof(wself) sself = wself; if (!sself) return;
            [sself _storeImage:image forURL:urlStr];
        }];
        if (op) { [self.runningOperations addObject:op]; }
    } else {
    }
    
    // Do not add per-image gestures; use container-level onContainerTapped: for hit testing
    imageView.tag = self.contentSubviews.count; // for identification
    
    // Save URL into accessibilityLabel
    imageView.accessibilityLabel = imageURL;
    
    [self.contentContainer addSubview:imageView];
    [self.contentSubviews addObject:imageView];
}

// Image tap handling
// Container-level gesture hit test: find tapped imageView (its accessibilityLabel holds the URL)
- (void)onContainerTapped:(UITapGestureRecognizer *)gesture
{
    CGPoint p = [gesture locationInView:self.contentContainer];
    // Search back-to-front, prioritizing the topmost view
    for (UIView *sub in self.contentSubviews.reverseObjectEnumerator) {
        if ([sub isKindOfClass:[UIImageView class]]) {
            if (CGRectContainsPoint(sub.frame, p)) {
                NSString *imageURL = sub.accessibilityLabel;
                if (imageURL.length > 0 && self.onImageTapHandler) {
                    self.onImageTapHandler(imageURL);
                }
                break;
            }
        }
    }
}

// Set image tap callback
- (void)setImageTapHandler:(void (^)(NSString *imageURL))handler
{
    self.onImageTapHandler = handler;
}

@end
