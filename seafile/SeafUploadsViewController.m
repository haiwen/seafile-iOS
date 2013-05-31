//
//  SeafUploadsViewController.m
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SeafUploadsViewController.h"
#import "SeafAppDelegate.h"
#import "SeafDetailViewController.h"
#import "SeafUploadingFileCell.h"
#import "SeafUploadDirViewController.h"
#import "SeafUploadFile.h"
#import "SeafRepos.h"
#import "SeafCell.h"

#import "CZPhotoPickerController.h"

#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "Debug.h"

@interface SeafUploadsViewController ()
@property NSMutableArray *entries;
@property NSMutableDictionary *attrs;
@property (readonly) UIImage *cellImage;

@property (readonly) SeafDetailViewController *detailViewController;
@property (retain) NSIndexPath *selectedindex;
@property (retain) CZPhotoPickerController *picker;
@property (retain)  NSDateFormatter *formatter;

@property (retain) InputAlertPrompt *addFileView;

@end

@implementation SeafUploadsViewController
@synthesize entries = _entries;
@synthesize attrs = _attrs;
@synthesize cellImage = _cellImage;
@synthesize connection = _connection;
@synthesize selectedindex = _selectedindex;
@synthesize addFileView = _addFileView;

@synthesize picker;
@synthesize formatter;

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
    }
    return self;
}

-(UIImage *)cellImage
{
    if (!_cellImage)
        _cellImage = [[UIImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"upload" ofType:@"png"]];
    return _cellImage;
}

- (SeafDetailViewController *)detailViewController
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    return (SeafDetailViewController *)[appdelegate detailViewController:TABBED_UPLOADS];
}

- (NSString *)attrsFile
{
    return [[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploadattrs.plist"];
}

- (void)saveAttrs
{
    [_attrs writeToFile:self.attrsFile atomically:YES];
}

- (void)loadEntries
{
    _attrs = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    for (int i = 0; i < [_entries count]; ++i) {
        SeafUploadFile *obj = [_entries objectAtIndex:i];
        [dict setObject:obj forKey:obj.name];
    }

    NSMutableArray *newentries = [[NSMutableArray alloc] init];
    NSMutableDictionary *attributes = [[NSMutableDictionary alloc] initWithContentsOfFile:self.attrsFile];
    NSError *error = nil;
    NSString *uploadPath = [[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"];
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:uploadPath error:&error];
    if (!dirContents) {
        Debug("unable to get the contents of uploads directory:%@\n", error);
        return;
    }

    for (NSString *name in dirContents) {
        BOOL isDirectory = NO;
        NSString *path = [uploadPath stringByAppendingPathComponent:name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) {
            if (isDirectory)
                [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            else {
                SeafUploadFile *file = [dict objectForKey:name];
                if (!file) {
                    file = [[SeafUploadFile alloc] initWithPath:path];
                    file.delegate = self;
                }
                [newentries addObject:file];
                if (attributes && [attributes objectForKey:name])
                    [ _attrs setObject:[attributes objectForKey:name] forKey:name];
            }
        }
    }
    [newentries sortUsingComparator:(NSComparator)^NSComparisonResult(id obj1, id obj2){
        return [[(SeafUploadFile *)obj1 name] caseInsensitiveCompare:[(SeafUploadFile *)obj2 name]];
    }];
    _entries = newentries;
    [self saveAttrs];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self loadEntries];
    [self.tableView reloadData];
}

- (void)delayupload
{
    [self uploadFile:_selectedindex];
}

- (void)addPhotos:(id)sender
{
    if (self.picker)
        return;
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    picker = [[CZPhotoPickerController alloc] initWithPresentingViewController:appdelegate.tabbarController withCompletionBlock:^(UIImagePickerController *imagePickerController, NSDictionary *imageInfoDict) {
        NSString *filename;
        self.picker = nil;
        UIImage *image = [imageInfoDict objectForKey:@"UIImagePickerControllerOriginalImage"];
        if (image) {
            filename = [NSString stringWithFormat:@"Photo %@.jpg", [formatter stringFromDate:[NSDate date]]];
            NSString *path = [[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"] stringByAppendingPathComponent:filename];
            [UIImageJPEGRepresentation(image, 1.0) writeToFile:path atomically:YES];
        }

        if (self.modalViewController)
            [self dismissViewControllerAnimated:YES completion:nil];
        if (!image)
            return;

        [self loadEntries];
        [self.tableView reloadData];
        int i = 0;
        _selectedindex = nil;
        for (SeafUploadFile *ufile in self.entries) {
            if ([ufile.name isEqualToString:filename]) {
                _selectedindex = [NSIndexPath indexPathForRow:i inSection:0];
                break;
            }
            ++i;
        }
        if (IsIpad()) {
            [self uploadFile:_selectedindex];
        } else {
            [self performSelector:@selector(delayupload) withObject:self afterDelay:0.5];
        }
    }];
    picker.allowsEditing = NO;
    [picker showFromBarButtonItem:sender];
}

- (void)addFile:(id)sender
{
    _addFileView = [[InputAlertPrompt alloc] initWithTitle:@"New file" delegate:self autoDismiss:YES];
    _addFileView.inputTextField.placeholder = @"New file name";
    _addFileView.inputTextField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _addFileView.inputTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _addFileView.inputTextField.returnKeyType = UIReturnKeyDone;
    _addFileView.inputTextField.autocorrectionType = UITextAutocapitalizationTypeNone;
    _addFileView.inputDoneDelegate = self;
    [_addFileView show];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;

    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    self.tableView.rowHeight = 50;
    [self loadEntries];
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    UIBarButtonItem *photoItem  = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCamera target:self action:@selector(addPhotos:)];
#if 1
    self.navigationItem.leftBarButtonItems = [NSArray arrayWithObjects:photoItem, nil];
#else
    UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addFile:)];
    self.navigationItem.leftBarButtonItems = [NSArray arrayWithObjects:addItem, photoItem, nil];
#endif
    self.formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH.mm.ss"];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)chooseUploadDir:(SeafDir *)dir
{
    [[_entries objectAtIndex:_selectedindex.row] upload:_connection repo:dir.repoId path:dir.path update:NO];
}

- (void)uploadFile:(NSIndexPath *)index
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    _selectedindex = index;
    SeafUploadDirViewController *controller = [[SeafUploadDirViewController alloc] initWithSeafDir:_connection.rootFolder];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    [navController setModalPresentationStyle:UIModalPresentationFormSheet];
    [appdelegate.tabbarController presentViewController:navController animated:YES completion:nil];
}

- (void)deleteFile:(NSIndexPath *)index
{
    // Delete the row from the data source
    SeafUploadFile *file = [_entries objectAtIndex:index.row];
    [_entries removeObjectAtIndex:index.row];
    [_attrs removeObjectForKey:file.name];
    [self saveAttrs];
    [file removeFile];
    [self.tableView reloadData];
}

#pragma mark - SeafUploadDelegate
- (void)uploadProgress:(SeafUploadFile *)file result:(BOOL)res completeness:(int)percent
{
    if (!res || (res && percent == 100)) {
        NSMutableDictionary *dict = [_attrs objectForKey:file.name];
        if (!dict) {
            dict = [[NSMutableDictionary alloc] init];
            [dict setObject:file.name forKey:@"name"];
        }
        [dict setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]]forKey:@"utime"];
        [dict setObject:[NSNumber numberWithBool:res] forKey:@"result"];
        [_attrs setObject:dict forKey:file.name];
        [self saveAttrs];
    }

    int index = [_entries indexOfObject:file];
    //Debug("index=%d, res=%d, percent=%d\n", index, res, percent);
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (res && file.uploading && [cell isKindOfClass:[SeafUploadingFileCell class]]) {
        [((SeafUploadingFileCell *)cell).progressView setProgress:percent*1.0f/100];
        return;
    }
    [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationAutomatic ];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _entries.count;
}

- (void)btnClicked:(id)sender event:(id)event
{
    NSSet *touches =[event allTouches];
    UITouch *touch =[touches anyObject];
    CGPoint currentTouchPosition = [touch locationInView:self.tableView];
    NSIndexPath *indexPath= [self.tableView indexPathForRowAtPoint:currentTouchPosition];
    if (indexPath!= nil) {
        [self tableView:self.tableView accessoryButtonTappedForRowWithIndexPath:indexPath];
    }
}

- (void)showEditMenu:(UILongPressGestureRecognizer *)gestureRecognizer
{
    UIActionSheet *actionSheet;
    if (gestureRecognizer.state != UIGestureRecognizerStateBegan)
        return;
    CGPoint touchPoint = [gestureRecognizer locationInView:self.tableView];
    _selectedindex = [self.tableView indexPathForRowAtPoint:touchPoint];
    if (!_selectedindex)
        return;
    if (IsIpad())
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:@"Upload", @"Delete", nil];
    else
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Upload", @"Delete", nil];

    Debug("index=%d\n", _selectedindex.row);
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:_selectedindex];
    [actionSheet showFromRect:cell.frame inView:self.tableView animated:YES];
}

- (UITableViewCell *)getCell:tableView file:(SeafUploadFile *)file
{
    NSString *CellIdentifier = @"SeafCell";
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:@"SeafCell" owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    cell.textLabel.text = file.name;
    cell.imageView.image = file.image;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0,0,24,24);;
    [button setBackgroundImage:self.cellImage forState:UIControlStateNormal];
    button.backgroundColor= [UIColor clearColor];
    [button addTarget:self action:@selector(btnClicked:event:) forControlEvents:UIControlEventTouchUpInside];

    NSString *sizeStr = [FileSizeFormatter stringFromNumber:[NSNumber numberWithInt:file.filesize ] useBaseTen:NO];
    NSDictionary *dict = [_attrs objectForKey:file.name];
    if (dict) {
        int utime = [[dict objectForKey:@"utime"] intValue];
        BOOL result = [[dict objectForKey:@"result"] boolValue];
        if (result)
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@, Uploaded %@", sizeStr, [SeafDateFormatter stringFromInt:utime]];
        else {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@, Failed %@", sizeStr, [SeafDateFormatter stringFromInt:utime]];
            cell.accessoryView = button;
        }
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@, Select folder to upload", sizeStr];
        cell.accessoryView = button;
    }
    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showEditMenu:)];
    [cell addGestureRecognizer:longPressGesture];
    return cell;
}

- (SeafUploadingFileCell *)getUploadingCell:tableView file:(SeafUploadFile *)file
{
    NSString *CellIdentifier = @"SeafUploadingFileCell";
    SeafUploadingFileCell *cell = (SeafUploadingFileCell *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    cell.nameLabel.text = file.name;
    cell.imageView.image = file.image;
    [cell.progressView setProgress:file.uploadProgress *1.0/100];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafUploadFile *file = [_entries objectAtIndex:indexPath.row];
    if (file.uploading)
        return [self getUploadingCell:tableView file:file];
    else
        return [self getCell:tableView file:file];
}


// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    SeafUploadFile *file = [_entries objectAtIndex:indexPath.row];
    if (file.uploading)
        return NO;
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleDelete;
}

// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self deleteFile:indexPath];
    }
}

// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the item to be re-orderable.
    return NO;
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    [self uploadFile:indexPath];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"Recent";
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SeafUploadFile *file = [_entries objectAtIndex:indexPath.row];
    if (!IsIpad()) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        [appdelegate showDetailView:self.detailViewController];
    }
    [self.detailViewController setPreViewItem:file];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}


#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 0) {
        [self uploadFile:_selectedindex];
    } else if (buttonIndex == 1) {
        [self deleteFile:_selectedindex];
    }
}

#pragma mark - UIAlertViewDelegate
- (void)didPresentAlertView:(UIAlertView *)alertView
{
    if ([alertView isKindOfClass:[InputAlertPrompt class]]) {
    }
}

- (void)alertView:(UIAlertView *)alertView willDismissWithButtonIndex:(NSInteger)buttonIndex
{
    _addFileView = nil;
}

#pragma mark - InputDoneDelegate
- (BOOL)inputDone:(InputAlertPrompt *)alertView input:(NSString *)input errmsg:(NSString **)errmsg;
{
    if (!input || input.length < 1) {
        *errmsg = @"A valid filename is needed";
        return NO;
    }
    NSString *path = [[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"] stringByAppendingPathComponent:input];

    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        *errmsg = @"The file already exists";
        return NO;
    } else if (![[NSFileManager defaultManager] createFileAtPath:path contents:[NSData data] attributes:nil]) {
        *errmsg = @"Failed to create file";
        return NO;
    }
    [self loadEntries];
    [self.tableView reloadData];
    return YES;
}

@end
