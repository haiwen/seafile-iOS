//
//  SeafBackupDirViewController.m
//  seafile
//
//  Created by Henry on 2025/6/9.
//  Copyright © 2024 Seafile Ltd. All rights reserved.
//

#import "SeafBackupDirViewController.h"
#import "SeafCell.h"
#import "SeafDir.h"
#import "SeafRepos.h"
#import "Debug.h"

@interface SeafBackupDirViewController ()
@property (strong, readonly) SeafDir *directory;
@property (readwrite) BOOL chooseRepo;
@property (nonatomic, strong) NSArray *subDirs;
@property (nonatomic, weak) id<SeafDirDelegate> delegate;
@end

@implementation SeafBackupDirViewController

- (id)initWithSeafDir:(SeafDir *)dir delegate:(id<SeafDirDelegate>)delegate chooseRepo:(BOOL)chooseRepo
{
    if (self = [super initWithSeafDir:dir delegate:delegate chooseRepo:chooseRepo]) {
        _directory = dir;
        _chooseRepo = chooseRepo;
        self.delegate = delegate;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.estimatedRowHeight = 50.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    self.tableView.tableFooterView = [UIView new];
    self.tableView.showsVerticalScrollIndicator = NO;
}

- (NSArray *)subDirs
{
    if (!_subDirs) {
        NSMutableArray *arr = [NSMutableArray new];
        if ([_directory isKindOfClass:[SeafRepos class]]) {
            SeafRepos *repos = (SeafRepos *)_directory;
            for (int i = 0; i < repos.repoGroups.count; ++i) {
                for (SeafRepo *repo in [repos.repoGroups objectAtIndex:i]) {
                    if (!_chooseRepo || repo.editable) {
                        [arr addObject:repo];
                    }
                }
            }
        } else {
            for (SeafDir *dir in _directory.subDirs) {
                if (!_chooseRepo || dir.editable) {
                    [arr addObject:dir];
                }
            }
        }
        _subDirs = [NSArray arrayWithArray:arr];
    }
    return _subDirs;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    _subDirs = nil;
    return self.subDirs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafDirCell";
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    [cell reset];

    @try {
        SeafDir *sdir = [self.subDirs objectAtIndex:indexPath.row];
        cell.textLabel.text = sdir.name;
        cell.imageView.image = sdir.icon;
        cell.moreButton.hidden = YES;
        cell.detailTextLabel.text = @"";
        if ([sdir isKindOfClass:[SeafRepo class]]) {
            SeafRepo *repo = (SeafRepo *)sdir;
            if (repo.isGroupRepo) {
                if (repo.owner.length > 0) {
                    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@, %@", repo.detailText, repo.owner];
                }
            } else {
                cell.detailTextLabel.text = repo.detailText;
            }
            
            UIImageView *accessoryView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
            if (self.selectedRepo && [self.selectedRepo.repoId isEqualToString:repo.repoId]) {
                accessoryView.image = [UIImage imageNamed:@"ic_checkbox_checked"];
            } else {
                accessoryView.image = [UIImage imageNamed:@"ic_checkbox_unchecked"];
            }
            cell.accessoryView = accessoryView;

            if (repo.encrypted) {
                cell.accessoryView = nil;
                cell.userInteractionEnabled = NO;
                cell.textLabel.alpha = 0.5;
                cell.detailTextLabel.alpha = 0.5;
            } else {
                cell.userInteractionEnabled = YES;
                cell.textLabel.alpha = 1.0;
                cell.detailTextLabel.alpha = 1.0;
            }

        } else {
            cell.accessoryView = nil;
        }
    } @catch(NSException *exception) {
        Warning("exception: %@", exception);
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafDir *sdir = [self.subDirs objectAtIndex:indexPath.row];
    if (![sdir isKindOfClass:[SeafRepo class]]) {
        return;
    }
    SeafRepo *repo = (SeafRepo *)sdir;
    if (repo.encrypted) {
        return;
    }

    SeafRepo *repoToSelect = repo;
    if (self.selectedRepo && [self.selectedRepo.repoId isEqualToString:repo.repoId]) {
        repoToSelect = nil;
    }
    [self.delegate chooseDir:self dir:repoToSelect];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 0;
}

@end 
