//  SeafCollaboratorChipCell.m

#import "SeafCollaboratorChipCell.h"

static UIImage *SeafDefaultAvatarImage(void)
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

@interface SeafCollaboratorChipCell ()
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) NSURLSessionDataTask *avatarTask;
@property (nonatomic, copy) NSString *avatarURLString;
@end

@implementation SeafCollaboratorChipCell

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        self.contentView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        self.contentView.layer.cornerRadius = 16;
        self.contentView.layer.masksToBounds = YES;

        UIStackView *h = [UIStackView new];
        h.axis = UILayoutConstraintAxisHorizontal;
        h.alignment = UIStackViewAlignmentCenter;
        h.spacing = 4;
        h.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:h];

        _avatarView = [UIImageView new];
        _avatarView.contentMode = UIViewContentModeScaleAspectFill;
        _avatarView.layer.cornerRadius = 9;
        _avatarView.layer.masksToBounds = YES;
        _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        [_avatarView.widthAnchor constraintEqualToConstant:18].active = YES;
        [_avatarView.heightAnchor constraintEqualToConstant:18].active = YES;

        _nameLabel = [UILabel new];
        _nameLabel.font = [UIFont systemFontOfSize:15];
        _nameLabel.textColor = [UIColor secondaryLabelColor];

        [h addArrangedSubview:_avatarView];
        [h addArrangedSubview:_nameLabel];

        [NSLayoutConstraint activateConstraints:@[
            [h.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
            [h.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
            [h.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:2],
            [h.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-2]
        ]];
    }
    return self;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    // cancel inflight
    [self.avatarTask cancel];
    self.avatarTask = nil;
    self.avatarURLString = nil;
    self.avatarView.image = SeafDefaultAvatarImage();
    self.nameLabel.text = @"";
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat h = CGRectGetHeight(self.contentView.bounds);
    self.contentView.layer.cornerRadius = h * 0.5;
    self.avatarView.layer.cornerRadius = 9;
}

- (void)configureWithName:(NSString *)name avatarURL:(NSString *)avatarURL
{
    self.nameLabel.text = name ?: @"";
    // simple cache
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSCache new]; cache.countLimit = 200; });

    // reset previous task
    [self.avatarTask cancel];
    self.avatarTask = nil;
    self.avatarURLString = avatarURL;

    if (avatarURL.length == 0) {
        self.avatarView.image = SeafDefaultAvatarImage();
        return;
    }

    UIImage *cached = [cache objectForKey:avatarURL];
    if (cached) {
        self.avatarView.image = cached;
        return;
    }

    self.avatarView.image = SeafDefaultAvatarImage();
    NSURL *url = [NSURL URLWithString:avatarURL];
    if (!url) return;

    __weak typeof(self) wself = self;
    self.avatarTask = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error || data.length == 0) return;
        UIImage *img = [UIImage imageWithData:data scale:[UIScreen mainScreen].scale];
        if (!img) return;
        [cache setObject:img forKey:avatarURL];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) sself = wself; if (!sself) return;
            // ensure not reused
            if ([sself.avatarURLString isEqualToString:avatarURL]) {
                sself.avatarView.image = img;
            }
        });
    }];
    [self.avatarTask resume];
}

@end

