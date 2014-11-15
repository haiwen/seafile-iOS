//
//  DocumentPickerViewController.m
//  SeafProvider
//
//  Created by Wang Wei on 11/12/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import "DocumentPickerViewController.h"
#import "SeafProviderFileViewController.h"
#import "SeafConnection.h"
#import "SeafGlobal.h"
#import "Debug.h"


@interface DocumentPickerViewController ()<UITableViewDataSource, UITableViewDelegate>
@property (strong, nonatomic) IBOutlet UITableView *tableView;
@property (strong) NSArray *conns;
@end

@implementation DocumentPickerViewController

-(void)prepareForPresentationInMode:(UIDocumentPickerMode)mode
{
    Debug("mode=%d", mode);
    [SeafGlobal.sharedObject loadAccounts];
    _conns = SeafGlobal.sharedObject.conns;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
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

#pragma mark - Table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafConnection *conn = [SeafGlobal.sharedObject.conns objectAtIndex:indexPath.row];
    [self pushViewControllerDir:(SeafDir *)conn.rootFolder];
}

- (void)pushViewControllerDir:(SeafDir *)dir
{
    SeafProviderFileViewController *controller = [[UIStoryboard storyboardWithName:@"SeafProviderFileViewController" bundle:nil] instantiateViewControllerWithIdentifier:@"SeafProviderFileViewController"];
    controller.directory = dir;
    controller.root = self;
    controller.view.frame = CGRectMake(self.view.frame.size.width, self.view.frame.origin.y, self.view.frame.size.width, self.view.frame.size.height);

    [self addChildViewController:controller];
    [controller didMoveToParentViewController:self];
    [self.view addSubview:controller.view];
    [UIView animateWithDuration:0.5f delay:0.f options:0 animations:^{
        controller.view.frame = self.view.frame;
    } completion:^(BOOL finished) {
    }];
}

@end
