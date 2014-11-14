//
//  DocumentPickerViewController.m
//  SeafProvier
//
//  Created by Wang Wei on 11/12/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import "DocumentPickerViewController.h"
#import "SeafConnection.h"
#import "SeafGlobal.h"
#import "Debug.h"


@interface DocumentPickerViewController ()<UITableViewDataSource, UITableViewDelegate>
@property (strong, nonatomic) IBOutlet UITableView *tableView;
@property (strong) NSArray *conns;
@end

@implementation DocumentPickerViewController

-(void)prepareForPresentationInMode:(UIDocumentPickerMode)mode {
    [SeafGlobal.sharedObject loadAccounts];
    _conns = SeafGlobal.sharedObject.conns;
    [self.tableView reloadData];
}


#pragma mark - Table view data source
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.conns.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafProviderAccountCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }
    SeafConnection *conn = [self.conns objectAtIndex:indexPath.row];
    cell.imageView.image = [UIImage imageWithContentsOfFile:[conn avatarForEmail:conn.username]];
    cell.textLabel.text = conn.address;
    cell.detailTextLabel.text = conn.username;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 64;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleNone;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSString *text = [NSString stringWithFormat:@"%ld accounts", self.conns.count];
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, tableView.bounds.size.width - 10, 18)];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor clearColor];
    [headerView setBackgroundColor:HEADER_COLOR];
    [headerView addSubview:label];

    return headerView;
}


#pragma mark - Table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    Debug("...");
}

@end
