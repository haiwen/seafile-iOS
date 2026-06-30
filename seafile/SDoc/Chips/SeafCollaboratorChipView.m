//  SeafCollaboratorChipView.m
//  Reusable capsule view for collaborator display (avatar + name).

#import "SeafCollaboratorChipView.h"

static UIImage *SeafChipDefaultAvatarImage(void)
{
    UIImage *img = [UIImage imageNamed:@"default_avatar"];
    if (img) return img;
    CGFloat side = 40.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [[UIColor colorWithWhite:0.9 alpha:1.0] setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, side, side));
    UIImage *generated = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return generated;
}

/// Shared avatar image cache (process-wide)
static NSCache<NSString *, UIImage *> *SeafChipAvatarCache(void)
{
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSCache new]; cache.countLimit = 200; });
    return cache;
}

@interface SeafCollaboratorChipView ()
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) NSURLSessionDataTask *avatarTask;
@property (nonatomic, copy) NSString *avatarURLString;
@end

@implementation SeafCollaboratorChipView

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super initWithCoder:coder]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI
{
    // Capsule background: light gray, fully rounded
    self.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    self.layer.masksToBounds = YES;

    UIStackView *h = [UIStackView new];
    h.axis = UILayoutConstraintAxisHorizontal;
    h.alignment = UIStackViewAlignmentCenter;
    h.spacing = 4;
    h.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:h];

    _avatarView = [UIImageView new];
    _avatarView.contentMode = UIViewContentModeScaleAspectFill;
    // Avatar size: 16px per design spec
    _avatarView.layer.cornerRadius = 8;
    _avatarView.layer.masksToBounds = YES;
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    [_avatarView.widthAnchor constraintEqualToConstant:16].active = YES;
    [_avatarView.heightAnchor constraintEqualToConstant:16].active = YES;

    _nameLabel = [UILabel new];
    _nameLabel.font = [UIFont systemFontOfSize:15];
    // Text color: #212529 per design spec
    _nameLabel.textColor = [UIColor colorWithRed:0x21/255.0 green:0x25/255.0 blue:0x29/255.0 alpha:1.0];
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    [h addArrangedSubview:_avatarView];
    [h addArrangedSubview:_nameLabel];

    // Padding: left 4px, right 8px, top/bottom 3px per design spec
    [NSLayoutConstraint activateConstraints:@[
        [h.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
        [h.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [h.topAnchor constraintEqualToAnchor:self.topAnchor constant:3],
        [h.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-3]
    ]];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat h = CGRectGetHeight(self.bounds);
    self.layer.cornerRadius = h * 0.5;
}

- (void)configureWithName:(NSString *)name avatarURL:(NSString *)avatarURL
{
    self.nameLabel.text = name ?: @"";

    // Cancel previous task
    [self.avatarTask cancel];
    self.avatarTask = nil;
    self.avatarURLString = avatarURL;

    if (avatarURL.length == 0) {
        self.avatarView.image = SeafChipDefaultAvatarImage();
        return;
    }

    UIImage *cached = [SeafChipAvatarCache() objectForKey:avatarURL];
    if (cached) {
        self.avatarView.image = cached;
        return;
    }

    self.avatarView.image = SeafChipDefaultAvatarImage();
    NSURL *url = [NSURL URLWithString:avatarURL];
    if (!url) return;

    __weak typeof(self) wself = self;
    self.avatarTask = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error || data.length == 0) return;
        UIImage *img = [UIImage imageWithData:data scale:[UIScreen mainScreen].scale];
        if (!img) return;
        [SeafChipAvatarCache() setObject:img forKey:avatarURL];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself; if (!sself) return;
            if ([sself.avatarURLString isEqualToString:avatarURL]) {
                sself.avatarView.image = img;
            }
        });
    }];
    [self.avatarTask resume];
}

/// Intrinsic content size for auto layout (align with chip cell sizing)
- (CGSize)intrinsicContentSize
{
    CGFloat nameW = ceil([self.nameLabel.text sizeWithAttributes:@{NSFontAttributeName: self.nameLabel.font}].width);
    // left 4 + avatar 16 + spacing 4 + text + right 8
    CGFloat width = 4 + 16 + 4 + nameW + 8;
    return CGSizeMake(MAX(32, width), 22);
}

@end
