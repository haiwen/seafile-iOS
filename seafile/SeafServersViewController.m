//
//  SeafServersViewController.m
//  seafile
//
//  Created by Wang Wei on 11/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafServersViewController.h"
#import "SeafJSONRequestOperation.h"
#import "UIViewController+AlertMessage.h"
#import "Debug.h"

@interface NSString (HTTPExtensions)

- (BOOL)isHTTPURL;
- (NSString *)normalURL;
- (BOOL)isValidSeafileServer;
@end

@implementation NSString (HTTPExtensions)

- (BOOL)isHTTPURL
{
    if (self.length < 8)
        return NO;
    if (![self hasPrefix:@"http://"] && ![self hasPrefix:@"https://"])
        return NO;
    return YES;
}

- (NSString *)normalURL
{
    NSString *url = [self lowercaseString];
    if ([url hasSuffix:@"/"]) {
        url = [url substringToIndex:url.length-1];
    }
    return url;
}

- (BOOL)isValidSeafileServer
{
    NSURLResponse *response = nil;
    NSError *error = nil;

    NSURL *url = [[NSURL URLWithString:self] URLByAppendingPathComponent:@"api/ping/"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:1.0f];
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    Warning("url=%@, resp=%@\n", url, data);
    if (data) {
        NSString *res = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if ([@"\"pong\"" caseInsensitiveCompare:res] == NSOrderedSame) {
            return YES;
        }
    }
    return NO;
}
@end


@interface SeafServersViewController ()
@property NSMutableArray *urls;
@property StartViewController *startController;
@property InputAlertPrompt *inputPrompt;
@property NSOperationQueue *queue;
@end

@implementation SeafServersViewController
@synthesize startController;
@synthesize urls;
@synthesize inputPrompt;
@synthesize queue;

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
    }
    return self;
}

- (id)initWithController:(StartViewController *)controller
{
    if (self = [super init]) {
        startController = controller;
        queue = [[NSOperationQueue alloc] init];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    NSArray *urlArray = [[NSUserDefaults standardUserDefaults] objectForKey:@"urls"];
    if (urlArray && urlArray.count >= 1) {
        self.urls = [urlArray mutableCopy];
    } else {
        self.urls = [[NSMutableArray alloc] init];
    }
    if ([self.urls indexOfObject:DEFAULT_SERVER_URL] == NSNotFound)
        [self.urls addObject:DEFAULT_SERVER_URL];

    self.title = @"Choose a server";
    UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStyleBordered target:self action:@selector(cancel:)];
    UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithTitle:@"Add New Server" style:UIBarButtonItemStyleBordered target:self action:@selector(addServer:)];

    self.navigationItem.leftBarButtonItems = [NSArray arrayWithObjects:cancelItem, addItem, nil];
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    self.tableView.scrollEnabled = YES;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)cancel:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)addServer:(id)sender
{
    inputPrompt = [[InputAlertPrompt alloc] initWithTitle:@"Add a server" delegate:self autoDismiss:NO];
    inputPrompt.inputDoneDelegate = self;
    inputPrompt.inputTextField.text = @"http://";
    inputPrompt.inputTextField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    inputPrompt.inputTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    inputPrompt.inputTextField.returnKeyType = UIReturnKeyDone;
    inputPrompt.inputTextField.keyboardType = UIKeyboardTypeURL;
    inputPrompt.inputTextField.autocorrectionType = UITextAutocapitalizationTypeNone;
    [inputPrompt show];
}

#pragma mark - InputDoneDelegate
- (void)_addUrl:(NSString *)url
{
    [self.urls addObject:url];
    Debug("%@, %@\n", url, self.urls);
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:self.urls forKey:@"urls"];
    [userDefaults synchronize];
    [self.tableView reloadData];
}

- (BOOL)inputDone:(InputAlertPrompt *)alertView input:(NSString *)input errmsg:(NSString **)errmsg;
{
    if (!input || ![input isHTTPURL] ) {
        *errmsg = @"Server url invalid";
        return NO;
    }

    input = [input normalURL];
    if ([self.urls indexOfObject:input] != NSNotFound) {
        *errmsg =  @"Server already exists";
        return NO;
    }
    Debug("....");
    NSURL *url = [[NSURL URLWithString:input] URLByAppendingPathComponent:@"api/ping/"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    SeafJSONRequestOperation *operation = [SeafJSONRequestOperation
                                           JSONRequestOperationWithRequest:request
                                           success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
                                               if ([@"pong" caseInsensitiveCompare:JSON] == NSOrderedSame) {
                                                   [self.inputPrompt dismissWithClickedButtonIndex:0 animated:YES];
                                                   [self _addUrl:input];
                                               } else
                                                   [self alertWithMessage:@"The url seems not to be a seafile server"];
                                           }failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, NSData *data) {
                                               [self alertWithMessage:@"The url seems not to be a seafile server"];
                                           }];
    [queue addOperation:operation];
    return YES;
}

#pragma mark - Table view data source
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.urls.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"ServerCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    NSString *url =[self.urls objectAtIndex:indexPath.row];
    cell.textLabel.text = url;
    cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    return cell;
}


- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *url =[self.urls objectAtIndex:indexPath.row];
    if ([DEFAULT_SERVER_URL isEqualToString:url])
        return NO;
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSString *url = [self.urls objectAtIndex:indexPath.row];
        [self.urls removeObjectAtIndex:indexPath.row];
        [self.tableView reloadData];
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        [userDefaults setObject:self.urls forKey:@"urls"];
        [userDefaults setObject:nil forKey:url];
        [userDefaults synchronize];
    }
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleDelete;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    Debug("%d, %@\n", indexPath.row, [self.urls objectAtIndex:indexPath.row]);
    [startController selectServer:[self.urls objectAtIndex:indexPath.row]];
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

@end
