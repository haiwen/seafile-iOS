//
//  DocumentPickerViewController.m
//  SeafProvider
//
//  Created by Wang Wei on 11/9/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import "DocumentPickerViewController.h"
#import "SeafConnection.h"
#import "SeafAccountCell.h"
#import "Debug.h"

@interface DocumentPickerViewController ()<UITableViewDataSource, UITableViewDelegate>
@property (retain) NSMutableArray *conns;

@end

@implementation DocumentPickerViewController
@synthesize conns;

- (void)loadAccounts
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSArray *accounts = [userDefaults objectForKey:@"ACCOUNTS"];
    for (NSDictionary *account in accounts) {
        SeafConnection *conn = [[SeafConnection alloc] initWithUrl:[account objectForKey:@"url"] username:[account objectForKey:@"username"]];
        if (conn.username)
            [self.conns addObject:conn];
    }
}

- (IBAction)openDocument:(id)sender {
    NSURL* documentURL = [self.documentStorageURL URLByAppendingPathComponent:@"Untitled.txt"];
    
    // TODO: if you do not have a corresponding file provider, you must ensure that the URL returned here is backed by a file
    [self dismissGrantingAccessToURL:documentURL];
}

-(void)prepareForPresentationInMode:(UIDocumentPickerMode)mode {
    // TODO: present a view controller appropriate for picker mode here
    [self loadAccounts];
}



#pragma mark - Table view data source
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.conns.count+1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
#if 0
    NSString *CellIdentifier = @"SeafAccountCell";
    SeafAccountCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    SeafConnection *conn = [conns objectAtIndex:indexPath.row];
    cell.imageview.image = [UIImage imageWithContentsOfFile:[conn avatarForEmail:conn.username]];
    cell.serverLabel.text = conn.address;
    cell.emailLabel.text = conn.username;
#else
    UITableViewCell *cell = [[UITableViewCell alloc] init];
    cell.textLabel.text = @"server";
    cell.detailTextLabel.text = @"email";
#endif
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
}
@end
