//  SeafMentionSheetViewController.m
//
#import "SeafMentionSheetViewController.h"

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

@interface SeafMentionSheetCell : UITableViewCell
@property (nonatomic, strong) NSURLSessionDataTask *avatarTask;
@property (nonatomic, copy) NSString *avatarURLString;
- (void)configureWithUser:(NSDictionary *)user;
@end

@implementation SeafMentionSheetCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        self.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        self.detailTextLabel.font = [UIFont systemFontOfSize:13];
        self.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        self.imageView.layer.cornerRadius = 18.0;
        self.imageView.clipsToBounds = YES;
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat side = 36.0;
    self.imageView.frame = CGRectMake(16, floor((self.contentView.bounds.size.height - side)/2.0), side, side);
    CGFloat left = CGRectGetMaxX(self.imageView.frame) + 12.0;
    CGFloat width = self.contentView.bounds.size.width - left - 16.0;
    self.textLabel.frame = CGRectMake(left, 10, width, 22);
    self.detailTextLabel.frame = CGRectMake(left, CGRectGetMaxY(self.textLabel.frame) + 2, width, 18);
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [self.avatarTask cancel];
    self.avatarTask = nil;
    self.avatarURLString = nil;
    self.imageView.image = SeafDefaultAvatarImage();
}

- (void)configureWithUser:(NSDictionary *)user
{
    NSString *name = [user[@"name"] isKindOfClass:NSString.class] ? user[@"name"] : @"";
    NSString *email = [user[@"email"] isKindOfClass:NSString.class] ? user[@"email"] : @"";
    NSString *avatar = [user[@"avatarURL"] isKindOfClass:NSString.class] ? user[@"avatarURL"] : @"";
    self.textLabel.text = (name.length > 0) ? name : email;
    self.detailTextLabel.text = email;
    [self setAvatarURLStringSafely:avatar];
}

- (void)setAvatarURLStringSafely:(NSString *)avatarURL
{
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSCache new]; cache.countLimit = 200; });

    [self.avatarTask cancel];
    self.avatarTask = nil;
    self.avatarURLString = avatarURL;

    if (avatarURL.length == 0) {
        self.imageView.image = SeafDefaultAvatarImage();
        return;
    }
    UIImage *cached = [cache objectForKey:avatarURL];
    if (cached) {
        self.imageView.image = cached;
        return;
    }
    self.imageView.image = SeafDefaultAvatarImage();
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
                sself.imageView.image = img;
            }
        });
    }];
    [self.avatarTask resume];
}
@end

@interface SeafMentionSheetViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *allUsers;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredUsers;
@end

@implementation SeafMentionSheetViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = NSLocalizedString(@"Select member", nil);
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 60.0;
    [_tableView registerClass:SeafMentionSheetCell.class forCellReuseIdentifier:@"cell"];
    // Add a top spacer so the first row has larger distance from the sheet top, consistent with SDoc property sheet feel
    CGFloat topSpacer = 12.0;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, topSpacer)];
    header.backgroundColor = [UIColor clearColor];
    _tableView.tableHeaderView = header;
    [self.view addSubview:_tableView];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sp = self.sheetPresentationController;
        sp.detents = @[ UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent ];
        sp.prefersGrabberVisible = YES;
        sp.prefersScrollingExpandsWhenScrolledToEdge = YES;
        sp.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
    }
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
}

#pragma mark - Table
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _filteredUsers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafMentionSheetCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    if (indexPath.row < _filteredUsers.count) {
        [cell configureWithUser:_filteredUsers[indexPath.row]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row < _filteredUsers.count && self.onSelectUser) {
        self.onSelectUser(_filteredUsers[indexPath.row]);
    }
}

@end


