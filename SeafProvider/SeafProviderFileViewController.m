//
//  SeafProviderFileViewController.m
//  seafilePro
//
//  Created by Wang Wei on 11/14/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import "SeafProviderFileViewController.h"
#import "SeafFile.h"
#import "SeafRepos.h"
#import "Debug.h"

@interface SeafProviderFileViewController ()<SeafDentryDelegate, UIScrollViewDelegate>
@property (strong, nonatomic) IBOutlet UIButton *backButton;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;

@end

@implementation SeafProviderFileViewController

- (IBAction)goBack:(id)sender
{
    [self popViewController];
}

- (void)setDirectory:(SeafDir *)directory
{
    _directory = directory;
    _directory.delegate = self;
    [_directory loadContent:true];
    self.titleLabel.text = _directory.name;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.titleLabel.text = _directory.name;
    [self.tableView reloadData];
    [self.backButton addTarget:self action:@selector(goBack:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)alertWithMessage:(NSString*)message handler:(void (^)())handler;
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:message message:nil preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        handler();
    }];
    [alert addAction:cancelAction];
    [self presentViewController:alert animated:true completion:nil];
}
- (void)popupSetRepoPassword:(SeafRepo *)repo
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Password of this library", @"Seafile") message:nil preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    }];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *textfiled = [alert.textFields objectAtIndex:0];
        NSString *input = textfiled.text;
        if (!input || input.length == 0) {
            [self alertWithMessage:NSLocalizedString(@"Password must not be empty", @"Seafile")handler:^{
                [self popupSetRepoPassword:repo];
            }];
            return;
        }
        if (input.length < 3 || input.length  > 100) {
            [self alertWithMessage:NSLocalizedString(@"The length of password should be between 3 and 100", @"Seafile") handler:^{
                [self popupSetRepoPassword:repo];
            }];
            return;
        }
        [repo setDelegate:self];
        if ([repo->connection localDecrypt:repo.repoId])
            [repo checkRepoPassword:input];
        else
            [repo setRepoPassword:input];

    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.secureTextEntry = true;
    }];
    [alert addAction:cancelAction];
    [alert addAction:okAction];

    [self presentViewController:alert animated:true completion:nil];
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _directory.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafProviderCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }
    
    SeafBase *entry = [_directory.items objectAtIndex:indexPath.row];
    cell.textLabel.text = entry.name;
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    cell.imageView.image = entry.icon;
    cell.detailTextLabel.text = nil;
    return cell;
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafBase *entry = [_directory.items objectAtIndex:indexPath.row];
    if ([entry isKindOfClass:[SeafFile class]]) {
        Debug("select file: %@", entry.name);
        [self.root dismissGrantingAccessToURL:[(SeafFile *)entry exportURL]];
    } else if ([entry isKindOfClass:[SeafRepo class]] && [(SeafRepo *)entry passwordRequired]) {
        Debug("...");
        [self popupSetRepoPassword:(SeafRepo *)entry];
    } else if ([entry isKindOfClass:[SeafDir class]]) {
        Debug("...");
        [self pushViewControllerDir:(SeafDir *)entry];
    }
}

#pragma mark - SeafDentryDelegate
- (void)entry:(SeafBase *)entry updated:(BOOL)updated progress:(int)percent
{
    if (updated) {
        [self.tableView reloadData];
    }
}
- (void)entry:(SeafBase *)entry downloadingFailed:(NSUInteger)errCode
{
    if ([_directory hasCache]) {
        return;
    }
    
    //[SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load content of the directory", @"Seafile")];
    //[self.tableView reloadData];
    Warning("Failed to load directory content %@\n", _directory.name);
}

- (void)entry:(SeafBase *)entry repoPasswordSet:(BOOL)success
{
    //[SVProgressHUD dismiss];
    if (success) {
        [self pushViewControllerDir:(SeafDir *)entry];
    } else {
        //[SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Wrong library password", @"Seafile") duration:2.0];
        [self performSelector:@selector(popupSetRepoPassword:) withObject:entry afterDelay:1.0];
    }
}

- (void)pushViewControllerDir:(SeafDir *)dir
{
    SeafProviderFileViewController *controller = [[UIStoryboard storyboardWithName:@"SeafProviderFileViewController" bundle:nil] instantiateViewControllerWithIdentifier:@"SeafProviderFileViewController"];
    controller.directory = dir;
    controller.root = self.root;
    controller.view.frame = CGRectMake(self.view.frame.size.width, self.view.frame.origin.y, self.view.frame.size.width, self.view.frame.size.height);
    [self addChildViewController:controller];
    [controller didMoveToParentViewController:self];
    [self.view addSubview:controller.view];

    [UIView animateWithDuration:0.5f delay:0.f options:0 animations:^{
        controller.view.frame = self.view.frame;
    } completion:^(BOOL finished) {
    }];
}

- (void)popViewController
{
    [UIView animateWithDuration:0.5
                     animations:^{
                         self.view.frame = CGRectMake(self.view.frame.size.width, self.view.frame.origin.y, self.view.frame.size.width, self.view.frame.size.height);
                     }
                     completion:^(BOOL finished){
                         [self willMoveToParentViewController:self.parentViewController];
                         [self.view removeFromSuperview];
                         [self removeFromParentViewController];
                     }];
}

@end
