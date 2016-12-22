//
//  ActionViewController.m
//  SeafAction
//
//  Created by Wang Wei on 04/12/2016.
//  Copyright © 2016 Seafile. All rights reserved.
//

#import "ActionViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import "SeafActionDirViewController.h"
#import "SeafGlobal.h"
#import "SeafAccountCell.h"
#import "UIViewController+Extend.h"
#import "Debug.h"
#import "Utils.h"

@interface ActionViewController ()<UITableViewDataSource, UITableViewDelegate>

@property (strong) NSArray *conns;
@property (strong) SeafUploadFile *ufile;

@end

@implementation ActionViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    if (IsIpad()) {
        [self setPreferredContentSize:CGSizeMake(480.0f, 540.0f)];
    }

    [SeafGlobal.sharedObject loadAccounts];
    _conns = SeafGlobal.sharedObject.conns;

    // Get the item[s] we're handling from the extension context.

    // For example, look for an image and place it into an image view.
    // Replace this with something appropriate for the type[s] your extension supports.
    NSString *tmpdir = [SeafGlobal.sharedObject uniqueDirUnder:SeafGlobal.sharedObject.tempDir];
    if (![Utils checkMakeDir:tmpdir]) {
        Warning("Failed to create temp dir.");
        return [self alertWithTitle:NSLocalizedString(@"Failed to upload file", @"Seafile") handler:nil];
    }

    NSItemProviderCompletionHandler imageHandler = ^(UIImage *image, NSError *error) {
        Debug("load image: %@", error);
        if (error) {
            return [self handleFile:nil];
        }
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH'-'mm'-'ss"];

        NSString *name = [NSString stringWithFormat:@"IMG_%@.JPG", [formatter stringFromDate:[NSDate date]] ];
        NSURL *targetUrl = [NSURL fileURLWithPath:[tmpdir stringByAppendingPathComponent:name]];
        NSData *data = UIImageJPEGRepresentation(image, 1.0f);
        BOOL ret = [data writeToURL:targetUrl atomically:true];
        [self handleFile:ret ? targetUrl : nil];

    };

    NSItemProviderCompletionHandler urlHandler = ^(NSURL *url, NSError *error) {
        Debug("load file from url: %@", url);
        NSString *name = url.lastPathComponent;
        NSURL *targetUrl = [NSURL fileURLWithPath:[tmpdir stringByAppendingPathComponent:name]];
        BOOL ret = [Utils copyFile:url to:targetUrl];
        [self handleFile:ret ? targetUrl : nil];
    };

    for (NSExtensionItem *item in self.extensionContext.inputItems) {
        for (NSItemProvider *itemProvider in item.attachments) {
            Debug("itemProvider: %@", itemProvider);
            if ([itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeURL]) {
                [itemProvider loadItemForTypeIdentifier:(NSString *)kUTTypeURL options:nil completionHandler:urlHandler];
            } else if ([itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeImage]) {
                // This is an image.
                [itemProvider loadItemForTypeIdentifier:(NSString *)kUTTypeImage options:nil completionHandler:imageHandler];
            } else if ([itemProvider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeMovie]) {
                [itemProvider loadItemForTypeIdentifier:(NSString *)kUTTypeMovie options:nil completionHandler:urlHandler];
            } else {
                Warning("Unknown file type.");
                return [self handleFile:nil];
            }
            break;
        }

        if (_ufile) {
            // We only handle one file, so stop looking for more.
            break;
        }
    }
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Accounts", @"Seafile")
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:nil
                                                                            action:nil];
}

- (void)handleFile:(NSURL *)url {
    Debug("Received file : %@", url);
    if (!url) {
        Warning("Failed to load file.");
        [self alertWithTitle:NSLocalizedString(@"Failed to load file", @"Seafile") handler:nil];
        [self.extensionContext completeRequestReturningItems:self.extensionContext.inputItems completionHandler:nil];
    }
    Debug("Upload file %@ %lld", url, [Utils fileSizeAtPath1:url.path]);
    _ufile = [[SeafUploadFile alloc] initWithPath:url.path];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)cancel:(id)sender
{
    [_ufile doRemove];
   [self.extensionContext completeRequestReturningItems:self.extensionContext.inputItems completionHandler:nil];
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
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 64;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafAccountCell *cell = [SeafAccountCell getInstance:tableView WithOwner:self];
    SeafConnection *conn = [self.conns objectAtIndex:indexPath.row];
    cell.imageview.image = [UIImage imageWithContentsOfFile:conn.avatar];
    cell.serverLabel.text = conn.address;
    cell.emailLabel.text = conn.username;
    cell.imageview.layer.cornerRadius = 5;
    cell.imageview.clipsToBounds = YES;
    return cell;
}

#pragma mark - Table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafConnection *conn = [SeafGlobal.sharedObject.conns objectAtIndex:indexPath.row];
    Debug("TouchId for account %@ %@, %d", conn.address, conn.username, conn.touchIdEnabled);
    if (!conn.touchIdEnabled) {
        return [self pushViewControllerDir:(SeafDir *)conn.rootFolder];
    }
    [self checkTouchId:^(bool success) {
        if (success) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.0), dispatch_get_main_queue(), ^{
                [self pushViewControllerDir:(SeafDir *)conn.rootFolder];
            });
        }
    }];
}

- (void)pushViewControllerDir:(SeafDir *)dir
{
    SeafActionDirViewController *controller = [[SeafActionDirViewController alloc] initWithSeafDir:dir file:self.ufile];
    [self.navigationController pushViewController:controller animated:true];
}

@end
