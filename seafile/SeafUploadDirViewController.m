//
//  SeafUploadDirVontrollerViewController.m
//  seafile
//
//  Created by Wang Wei on 10/20/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafUploadDirViewController.h"
#import "SeafDirViewController.h"
#import "SeafAppDelegate.h"
#import "SeafDir.h"
#import "SeafRepos.h"

#import "UIViewController+Extend.h"
#import "Debug.h"


@interface SeafUploadDirViewController ()<SeafDirDelegate>
@property (strong) SeafConnection *connection;
@property (strong) SeafDir *curDir;
@property (strong) SeafUploadFile *ufile;
@property (strong, nonatomic) IBOutlet UIImageView *imageVIew;
@property (strong, nonatomic) IBOutlet UILabel *nameLabel;
@property (strong, nonatomic) IBOutlet UILabel *dirLabel;
@property (strong, nonatomic) IBOutlet UISwitch *replaceSwitch;

@property (strong, nonatomic) IBOutlet UILabel *replaceLabel;
@property (strong, nonatomic) IBOutlet UILabel *destinationLabel;

@property (strong) UIBarButtonItem *saveItem;

@end

@implementation SeafUploadDirViewController


- (id)initWithSeafConnection:(SeafConnection *)conn uploadFile:(SeafUploadFile *) ufile;
{
    if (self = [self initWithAutoNibName]) {
        self.connection = conn;
        self.ufile = ufile;
        self.title = [NSString stringWithFormat:NSLocalizedString(@"Save to %@", @"Seafile"), APP_NAME];

        NSString *repo = [SeafGlobal.sharedObject objectForKey: [@"LAST-REPO" stringByAppendingString:conn.address]];
        NSString *path = [SeafGlobal.sharedObject objectForKey:[@"LAST-DIR" stringByAppendingString:conn.address]];
        if (repo && path) {
            NSString *name = path.lastPathComponent;
            if (!name)
                name = @"/";
            self.curDir = [[SeafDir alloc] initWithConnection:conn oid:nil repoId:repo name:name.lastPathComponent path:path];
        }
        self.view.autoresizesSubviews = YES;
        for (UIView *v in self.view.subviews) {
            v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin| UIViewAutoresizingFlexibleRightMargin|  UIViewAutoresizingFlexibleBottomMargin;
        }
    }

    return self;
}

- (void)cancel:(id)sender
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)save:(id)sender
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    [SeafGlobal.sharedObject setObject:_curDir.repoId forKey:[@"LAST-REPO" stringByAppendingString:self.connection.address]];
    [SeafGlobal.sharedObject setObject:_curDir.path forKey:[@"LAST-DIR" stringByAppendingString:self.connection.address]];
    [SeafGlobal.sharedObject synchronize];
    [appdelegate.fileVC chooseUploadDir:_curDir file:self.ufile replace:self.replaceSwitch.isOn];
}

- (void)viewWillAppear:(BOOL)animated
{
    [self.navigationController setToolbarHidden:YES];
    if (self.curDir)
        [self.saveItem setEnabled:YES];
    else
        [self.saveItem setEnabled:NO];

    [super viewWillAppear:animated];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    // Uncomment the following line to preserve selection between presentations.
    self.saveItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Save", @"Seafile") style:UIBarButtonItemStyleBordered target:self action:@selector(save:)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Cancel", @"Seafile") style:UIBarButtonItemStyleBordered target:self action:@selector(cancel:)];
    self.navigationItem.rightBarButtonItem = self.saveItem;
    self.imageVIew.image = self.ufile.icon;
    self.nameLabel.text = self.ufile.name;
    if (self.curDir) {
        [self.saveItem setEnabled:YES];
        self.dirLabel.text = [[[self.connection getRepo:self.curDir.repoId] name]stringByAppendingString:self.curDir.path];
    } else {
        self.dirLabel.text = NSLocalizedString(@"Choose", @"Seafile");
        [self.saveItem setEnabled:NO];
    }
    _replaceLabel.text = NSLocalizedString(@"Replace", @"Seafile");
    _destinationLabel.text = NSLocalizedString(@"Destination", @"Seafile");
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)choose:(id)sender
{
    SeafDirViewController *c = [[SeafDirViewController alloc] initWithSeafDir:self.connection.rootFolder delegate:self chooseRepo:false];
    [self.navigationController pushViewController:c animated:YES];
}

#pragma mark - SeafDirDelegate
- (void)chooseDir:(UIViewController *)c dir:(SeafDir *)dir
{
    [self.navigationController popToRootViewControllerAnimated:YES];
    _curDir = dir;
    self.dirLabel.text = [[[self.connection getRepo:self.curDir.repoId] name] stringByAppendingString:self.curDir.path];
}
- (void)cancelChoose:(UIViewController *)c
{
    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)viewDidUnload
{
    [self setImageVIew:nil];
    [self setNameLabel:nil];
    [self setDirLabel:nil];
    [super viewDidUnload];
}

@end
