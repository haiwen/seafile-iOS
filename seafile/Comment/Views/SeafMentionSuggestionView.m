//  SeafMentionSuggestionView.m
//
#import "SeafMentionSuggestionView.h"
#import <UIKit/UIKit.h>

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

@interface SeafMentionSuggestionCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) NSURLSessionDataTask *avatarTask;
@property (nonatomic, copy) NSString *avatarURLString;
@end

@implementation SeafMentionSuggestionCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        self.backgroundColor = [UIColor systemBackgroundColor];
        self.contentView.backgroundColor = [UIColor systemBackgroundColor];
        _avatarView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _avatarView.clipsToBounds = YES;
        _avatarView.layer.cornerRadius = 18.0; // 36x36
        [self.contentView addSubview:_avatarView];
        self.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        self.detailTextLabel.font = [UIFont systemFontOfSize:12];
        self.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat padding = 10.0;
    CGFloat avatarSide = 36.0;
    _avatarView.frame = CGRectMake(padding, floor((self.contentView.bounds.size.height - avatarSide)/2.0), avatarSide, avatarSide);
    CGFloat textLeft = CGRectGetMaxX(_avatarView.frame) + 10.0;
    CGFloat textWidth = self.contentView.bounds.size.width - textLeft - padding;
    self.textLabel.frame = CGRectMake(textLeft, 0, textWidth, self.contentView.bounds.size.height);
    self.detailTextLabel.frame = CGRectZero;
    self.separatorInset = UIEdgeInsetsMake(0, textLeft, 0, 0);
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [self.avatarTask cancel];
    self.avatarTask = nil;
    self.avatarURLString = nil;
    self.avatarView.image = SeafDefaultAvatarImage();
}

- (void)setAvatarURLStringSafely:(NSString *)avatarURL
{
    // Lightweight avatar cache using NSCache + NSURLSession
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSCache new]; cache.countLimit = 200; });

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
            if ([sself.avatarURLString isEqualToString:avatarURL]) {
                sself.avatarView.image = img;
            }
        });
    }];
    [self.avatarTask resume];
}
@end

@interface SeafMentionSuggestionView () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *allUsers;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredUsers;
@end

@implementation SeafMentionSuggestionView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = 12.0;
        self.layer.masksToBounds = NO;
        self.backgroundColor = [UIColor systemBackgroundColor];
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.12;
        self.layer.shadowRadius = 8.0;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _tableView.backgroundColor = [UIColor clearColor];
        _tableView.separatorInset = UIEdgeInsetsMake(0, 56, 0, 0);
        _tableView.dataSource = self;
        _tableView.delegate = self;
        _tableView.rowHeight = 56.0;
        [_tableView registerClass:SeafMentionSuggestionCell.class forCellReuseIdentifier:@"cell"];
        [self addSubview:_tableView];
        self.hidden = YES;
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    _tableView.frame = self.bounds;
}

- (void)updateAllUsers:(NSArray<NSDictionary *> *)users
{
    _allUsers = users ?: @[];
    _filteredUsers = _allUsers;
    [_tableView reloadData];
}

- (void)applyFilter:(NSString * _Nullable)filter
{
    NSString *q = (filter ?: @"");
    if (q.length == 0) {
        _filteredUsers = _allUsers;
    } else {
        NSString *low = q.lowercaseString;
        NSPredicate *pred = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *u, NSDictionary<NSString *,id> * _Nullable bindings) {
            NSString *name = [u[@"name"] isKindOfClass:NSString.class] ? u[@"name"] : @"";
            NSString *email = [u[@"email"] isKindOfClass:NSString.class] ? u[@"email"] : @"";
            return ([name.lowercaseString containsString:low] ||
                    [email.lowercaseString containsString:low]);
        }];
        _filteredUsers = [_allUsers filteredArrayUsingPredicate:pred];
    }
    [_tableView reloadData];
    [self updateHeight];
    self.hidden = (_filteredUsers.count == 0);
}

- (void)showInView:(UIView *)parent belowView:(UIView *)anchorView
{
    if (!self.superview) {
        [parent addSubview:self];
    }
    // Position: anchored above the input bar (anchorView)
    CGFloat parentW = parent.bounds.size.width;
    CGFloat maxHeight = MIN(8 * 56.0, parent.bounds.size.height * 0.5);
    CGFloat width = parentW;
    CGFloat height = MIN(maxHeight, MAX(56.0, _filteredUsers.count * 56.0));
    CGRect anchorFrame = [parent convertRect:anchorView.bounds fromView:anchorView];
    CGFloat y = CGRectGetMinY(anchorFrame) - height;
    if (y < 0) y = 0;
    self.frame = CGRectMake(0, y, width, height);
    self.hidden = (_filteredUsers.count == 0);
}

- (void)hide
{
    self.hidden = YES;
}

#pragma mark - UITableView
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _filteredUsers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafMentionSuggestionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    NSDictionary *u = _filteredUsers[indexPath.row];
    NSString *name = [u[@"name"] isKindOfClass:NSString.class] ? u[@"name"] : @"";
    NSString *email = [u[@"email"] isKindOfClass:NSString.class] ? u[@"email"] : @"";
    NSString *avatar = [u[@"avatarURL"] isKindOfClass:NSString.class] ? u[@"avatarURL"] : @"";
    cell.textLabel.text = (name.length > 0) ? name : email;
    cell.detailTextLabel.text = nil;
    [cell setAvatarURLStringSafely:avatar];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row < _filteredUsers.count) {
        NSDictionary *u = _filteredUsers[indexPath.row];
        if (self.onSelectUser) self.onSelectUser(u);
    }
}

#pragma mark - Helpers
- (void)updateHeight
{
    CGFloat maxHeight = MIN(8 * 56.0, self.superview.bounds.size.height * 0.5);
    CGFloat target = MIN(maxHeight, MAX(56.0, _filteredUsers.count * 56.0));
    CGRect f = self.frame;
    f.size.height = target;
    self.frame = f;
}

@end


