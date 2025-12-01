//
//  SeafSdocStylePopupViewController.m
//  seafilePro
//
//  Created by Henry on 2024/11/25.
//

#import "SeafSdocStylePopupViewController.h"
#import "SeafGlobal.h"

@interface SeafSdocStylePopupViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *styleItems;
@property (nonatomic, strong) NSDictionary *styleTitles;
@property (nonatomic, strong) NSDictionary *styleFonts;

@end

@implementation SeafSdocStylePopupViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    self.preferredContentSize = CGSizeMake(200, 460); // Width and estimated height
    
    [self initData];
    [self setupUI];
}

- (void)initData {
    // Order matching Android implementation
    self.styleItems = @[
        @"paragraph",
        @"title",
        @"subtitle",
        @"header1",
        @"header2",
        @"header3",
        @"header4",
        @"header5",
        @"header6"
    ];
    
    self.styleTitles = @{
        @"paragraph": NSLocalizedString(@"Paragraph", nil),
        @"title": NSLocalizedString(@"Title", nil),
        @"subtitle": NSLocalizedString(@"Subtitle", nil),
        @"header1": NSLocalizedString(@"Heading 1", nil),
        @"header2": NSLocalizedString(@"Heading 2", nil),
        @"header3": NSLocalizedString(@"Heading 3", nil),
        @"header4": NSLocalizedString(@"Heading 4", nil),
        @"header5": NSLocalizedString(@"Heading 5", nil),
        @"header6": NSLocalizedString(@"Heading 6", nil)
    };
    
    // Font sizes matching Android sp values roughly (Android sp -> iOS pt)
    // Title: 30sp -> ~30pt
    // H1: 24sp -> ~24pt
    // H2: 22sp -> ~22pt
    // H3: 20sp -> ~20pt
    // H4: 18sp -> ~18pt
    // H5: 16sp -> ~16pt
    // H6: 14sp -> ~14pt
    // Subtitle: 18sp -> ~18pt
    // Paragraph: Default ~16pt
    self.styleFonts = @{
        @"paragraph": [UIFont systemFontOfSize:16],
        @"title": [UIFont boldSystemFontOfSize:30],
        @"subtitle": [UIFont systemFontOfSize:18],
        @"header1": [UIFont boldSystemFontOfSize:24],
        @"header2": [UIFont boldSystemFontOfSize:22],
        @"header3": [UIFont boldSystemFontOfSize:20],
        @"header4": [UIFont boldSystemFontOfSize:18],
        @"header5": [UIFont boldSystemFontOfSize:16],
        @"header6": [UIFont boldSystemFontOfSize:14]
    };
}

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone; // Custom separators or none
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 44;
    self.tableView.tableFooterView = [UIView new];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.styleItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"StyleCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
        
        // Setup checkmark icon view (hidden by default)
        UIImage *iconImage = [UIImage imageNamed:@"popup_window_icon"];
        if (!iconImage) {
            if (@available(iOS 13.0, *)) {
                iconImage = [UIImage systemImageNamed:@"checkmark"];
            } else {
                iconImage = [UIImage imageNamed:@"checkmask2"];
            }
        }
        UIImageView *checkIcon = [[UIImageView alloc] initWithImage:iconImage];
        
        checkIcon.tag = 100;
        checkIcon.contentMode = UIViewContentModeScaleAspectFit;
        checkIcon.translatesAutoresizingMaskIntoConstraints = NO;
        checkIcon.tintColor = [UIColor colorWithWhite:0.6 alpha:1.0]; // material_grey_500
        
        [cell.contentView addSubview:checkIcon];
        
        UILabel *label = [[UILabel alloc] init];
        label.tag = 101;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.numberOfLines = 1;
        [cell.contentView addSubview:label];
        
        // Constraints
        [NSLayoutConstraint activateConstraints:@[
            [checkIcon.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [checkIcon.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [checkIcon.widthAnchor constraintEqualToConstant:18],
            [checkIcon.heightAnchor constraintEqualToConstant:18],
            
            [label.leadingAnchor constraintEqualToAnchor:checkIcon.trailingAnchor constant:16],
            [label.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [label.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
            [label.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12]
        ]];
        
        // Divider for specific items if needed, matching Android logic
        // Android: Divider after paragraph and subtitle?
        // Android XML: Paragraph -> Divider -> Title -> Subtitle -> Divider -> H1...
        UIView *divider = [[UIView alloc] init];
        divider.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0]; // Light divider
        divider.tag = 102;
        divider.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:divider];
        
        [NSLayoutConstraint activateConstraints:@[
            [divider.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
            [divider.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
            [divider.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
            [divider.heightAnchor constraintEqualToConstant:1]
        ]];
    }
    
    NSString *styleKey = self.styleItems[indexPath.row];
    
    // Configure Cell
    UIImageView *checkIcon = [cell.contentView viewWithTag:100];
    UILabel *label = [cell.contentView viewWithTag:101];
    UIView *divider = [cell.contentView viewWithTag:102];
    
    label.text = self.styleTitles[styleKey];
    label.font = self.styleFonts[styleKey];
    
    // Icon visibility logic
    BOOL isSelected = [styleKey isEqualToString:self.currentStyle];
    checkIcon.hidden = !isSelected;
    
    // Divider logic matching Android
    // Android: Divider after "paragraph" (index 0) and "subtitle" (index 2)
    if (indexPath.row == 0 || indexPath.row == 2) {
        divider.hidden = NO;
    } else {
        divider.hidden = YES;
    }
    
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *selectedStyle = self.styleItems[indexPath.row];
    if (self.delegate && [self.delegate respondsToSelector:@selector(didSelectStyle:)]) {
        [self.delegate didSelectStyle:selectedStyle];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

