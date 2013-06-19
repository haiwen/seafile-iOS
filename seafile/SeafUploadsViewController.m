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

#import "QBImagePickerController.h"

#import "FileSizeFormatter.h"
#import "SeafDateFormatter.h"
#import "Debug.h"

@interface SeafUploadsViewController ()<QBImagePickerControllerDelegate, UIPopoverControllerDelegate>
@property NSMutableArray *entries;
@property NSMutableArray *selectedEntries;
@property NSMutableDictionary *attrs;
@property (readonly) UIImage *cellImage;

@property (readonly) SeafDetailViewController *detailViewController;
@property (retain) NSIndexPath *selectedindex;
@property (retain)  NSDateFormatter *formatter;

@property (retain) InputAlertPrompt *addFileView;
@property(nonatomic,strong) UIPopoverController *popoverController;

@end

@implementation SeafUploadsViewController
@synthesize entries = _entries;
@synthesize attrs = _attrs;
@synthesize cellImage = _cellImage;
@synthesize connection = _connection;
@synthesize selectedindex = _selectedindex;
@synthesize addFileView = _addFileView;
@synthesize popoverController;

@synthesize selectedEntries;
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
    if(self.popoverController)
        return;
    QBImagePickerController *imagePickerController = [[QBImagePickerController alloc] init];
    imagePickerController.delegate = self;
    imagePickerController.allowsMultipleSelection = YES;
    
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:imagePickerController];
    if (IsIpad()) {
        self.popoverController = [[UIPopoverController alloc] initWithContentViewController:navigationController];
        self.popoverController.delegate = self;
        [self.popoverController presentPopoverFromBarButtonItem:sender permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else {
        [self presentViewController:navigationController animated:YES completion:NULL];
    }
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
    for (SeafUploadFile *file in self.selectedEntries) {
        [file upload:_connection repo:dir.repoId path:dir.path update:NO];
    }
}

- (void)uploadFiles:(NSMutableArray *)arr
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    _selectedindex = nil;
    self.selectedEntries = arr;
    SeafUploadDirViewController *controller = [[SeafUploadDirViewController alloc] initWithSeafDir:_connection.rootFolder];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    [navController setModalPresentationStyle:UIModalPresentationFormSheet];
    [appdelegate.tabbarController presentViewController:navController animated:YES completion:nil];
}

- (void)uploadFile:(NSIndexPath *)index
{
    NSMutableArray *arr = [NSMutableArray arrayWithObject:[_entries objectAtIndex:index.row]];
    [self uploadFiles:arr];
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
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:currentTouchPosition];
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
    cell.accessoryView = nil;
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
    return @"Click at the arrow to upload";
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


#pragma mark - QBImagePickerControllerDelegate
- (void)imagePickerController:(QBImagePickerController *)imagePickerController didFinishPickingMediaWithInfo:(id)info
{
    if (IsIpad()) {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController = nil;
    } else {
        [self dismissViewControllerAnimated:YES completion:NULL];
    }
    if (imagePickerController.allowsMultipleSelection) {
        NSArray *mediaInfoArray = (NSArray *)info;
        Debug("Selected %d photos:%@\n", mediaInfoArray.count, mediaInfoArray);
    } else {
        NSDictionary *mediaInfo = (NSDictionary *)info;
        Debug("Selected: %@", mediaInfo);
    }

    NSMutableArray *files = [[NSMutableArray alloc] init];
    if (imagePickerController.allowsMultipleSelection) {
        int i = 0;
        NSString *date = [formatter stringFromDate:[NSDate date]];
        for (NSDictionary *dict in info) {
            i++;
            UIImage *image = [dict objectForKey:@"UIImagePickerControllerOriginalImage"];
            NSString *filename = [NSString stringWithFormat:@"Photo %@-%d.jpg", date, i];
            NSString *path = [[[Utils applicationDocumentsDirectory] stringByAppendingPathComponent:@"uploads"] stringByAppendingPathComponent:filename];
            [UIImageJPEGRepresentation(image, 1.0) writeToFile:path atomically:YES];
            SeafUploadFile *file =  [[SeafUploadFile alloc] initWithPath:path];
            file.delegate = self;
            [files addObject:file];
            [_entries addObject:file];
        }
    }
    [self.tableView reloadData];
    [self uploadFiles:files];
}

- (void)imagePickerControllerDidCancel:(QBImagePickerController *)imagePickerController
{
    if (IsIpad()) {
        [self.popoverController dismissPopoverAnimated:YES];
        self.popoverController = nil;
    } else {
        [self dismissViewControllerAnimated:YES completion:NULL];
    }
}

- (NSString *)descriptionForSelectingAllAssets:(QBImagePickerController *)imagePickerController
{
    return @"Select all photos";
}

- (NSString *)descriptionForDeselectingAllAssets:(QBImagePickerController *)imagePickerController
{
    return @"Deselect all photos";
}

- (NSString *)imagePickerController:(QBImagePickerController *)imagePickerController descriptionForNumberOfPhotos:(NSUInteger)numberOfPhotos
{
    return [NSString stringWithFormat:@"%d photos", numberOfPhotos];
}

- (NSString *)imagePickerController:(QBImagePickerController *)imagePickerController descriptionForNumberOfVideos:(NSUInteger)numberOfVideos
{
    return [NSString stringWithFormat:@"%d videos", numberOfVideos];
}

- (NSString *)imagePickerController:(QBImagePickerController *)imagePickerController descriptionForNumberOfPhotos:(NSUInteger)numberOfPhotos numberOfVideos:(NSUInteger)numberOfVideos
{
    return [NSString stringWithFormat:@"%d photos、%d videos", numberOfPhotos, numberOfVideos];
}

#pragma mark - UIPopoverControllerDelegate
- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
    self.popoverController = nil;
}
@end
