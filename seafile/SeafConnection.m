//
//  SeafConnection.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafConnection.h"
#import "SeafJSONRequestOperation.h"
#import "SeafRepos.h"
#import "SeafDir.h"
#import "SeafData.h"
#import "SeafAppDelegate.h"

#import "AFJSONUtilities.h"
#import "ExtentedString.h"
#import "Debug.h"
#import "Utils.h"

@interface SeafConnection ()

@property (readwrite) NSString *sessionid;
@property NSMutableSet *starredFiles;
- (void)testConnection;

@end

@implementation SeafConnection
@synthesize address = _address;
@synthesize info = _info;
@synthesize sessionid = _sessionid;
@synthesize delegate = _delegate;
@synthesize rootFolder = _rootFolder;
@synthesize starredFiles = _starredFiles;


- (id)init:(NSString *)url
{
    if (self = [super init]) {
        _address = url;
        queue = [[NSOperationQueue alloc] init];
        _rootFolder = [[SeafRepos alloc] initWithConnection:self];
    }
    return self;
}

- (id)initWithUrl:(NSString *)url
{
    self = [self init:url];
    if (!url) {
        _info = [[NSMutableDictionary alloc] init];
    } else {
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        NSDictionary *ainfo = [userDefaults objectForKey:url];
        if (ainfo) {
            _info = [ainfo mutableCopy];
            _sessionid = [_info objectForKey:@"sessionid"];
        } else {
            _info = [[NSMutableDictionary alloc] init];
        }
    }
    return self;
}

- (BOOL)logined
{
    return (_sessionid != nil);
}

- (NSString *)username
{
    return [_info objectForKey:@"username"];
}

- (NSString *)password
{
    return [_info objectForKey:@"password"];
}

- (NSString *)feedback
{
    return [_info objectForKey:@"feedback"];
}

- (long long)quota
{
    return [[_info objectForKey:@"total"] integerValue:0];
}

- (long long)usage
{
    return [[_info objectForKey:@"usage"] integerValue:-1];
}

- (void)estabilishConnection
{
    if (!_address) {
        [self.delegate connectionEstablishingFailed:self];
    } else {
        [self testConnection];
    }
}

- (void)handleAccountInfo:(id)data
{
    NSDictionary *account = data;
    [_info setObject:[account objectForKey:@"total"] forKey:@"total"];
    [_info setObject:[account objectForKey:@"usage"] forKey:@"usage"];
    [_info setObject:[account objectForKey:@"feedback"] forKey:@"feedback"];
    [_info setObject:_address forKey:@"link"];
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:_info forKey:_address];
    [userDefaults synchronize];
}

- (void)getAccountInfo:(id<SSConnectionAccountDelegate>)degt
{
    [self sendRequest:API_URL"/account/info/" repo:nil
              success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         [self handleAccountInfo:JSON];
         [degt getAccountInfoResult:YES connection:self];
     }
              failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
         [degt getAccountInfoResult:NO connection:self];
     }];
}


/*
 curl -D a.txt --data "username=pithier@163.com&password=pithier" http://www.gonggeng.org/seahub/api/login/
 */
- (void)loginWithAddress:(NSString *)anAddress username:(NSString *)username password:(NSString *)password
{
    if (!_address && anAddress)
        _address = anAddress;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[_address stringByAppendingString:API_URL"/auth-token/"]]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSString *formString = [NSString stringWithFormat:@"username=%@&password=%@",
                            [username stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding],
                            [password stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    NSData *requestData = [NSData dataWithBytes:[formString UTF8String] length:[formString length]];
    [request setHTTPBody:requestData];
    SeafJSONRequestOperation *operation = [SeafJSONRequestOperation
                                           JSONRequestOperationWithRequest:request
                                           success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
                                               _sessionid = [JSON objectForKey:@"token"];
                                               [_info setObject:username forKey:@"username"];
                                               [_info setObject:password forKey:@"password"];
                                               [_info setObject:_sessionid forKey:@"sessionid"];
                                               [_info setObject:_address forKey:@"link"];
                                               NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
                                               [userDefaults setObject:_info forKey:_address];
                                               [userDefaults synchronize];
                                               [self.delegate connectionLinkingSuccess:self];
                                           }
                                           failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, NSData *data){
                                               Warning("status code=%d\n", response.statusCode);
                                               [self.delegate connectionLinkingFailed:self error:response.statusCode];
                                           }];
    [queue addOperation:operation];
}

- (void)sendRequestAsync:(NSMutableURLRequest *)request repo:(NSString *)repoId
                 success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data))success
                 failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure
{
    NSString *password;
    if (_sessionid)
        [request setValue:[NSString stringWithFormat:@"Token %@", _sessionid] forHTTPHeaderField:@"Authorization"];

    if (repoId) {
        password = [Utils getRepoPassword:repoId];
        if (password) {
            [request setValue:password forHTTPHeaderField:@"password"];
        }
    }
    Debug("requestUrl=%@, sessionid=%@, password=%@\n", request.URL, _sessionid, password);

    [request setTimeoutInterval:10.0f];
    SeafJSONRequestOperation *operation = [SeafJSONRequestOperation JSONRequestOperationWithRequest:request success:success  failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        if (response.statusCode == HTTP_ERR_LOGIN_REUIRED && self.username && self.password) {
            [self loginWithAddress:nil username:self.username password:self.password];
        }
        failure (request, response, error, JSON);
    }];
    [queue addOperation:operation];
}

- (void)sendRequest:(NSString *)url repo:(NSString *)repoId
            success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data))success
            failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[_address stringByAppendingString:url]]];
    [self sendRequestAsync:request repo:repoId success:success failure:failure];
}

- (void)sendPost:(NSString *)url repo:(NSString *)repoId form:(NSString *)form
         success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data))success
         failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
                                    [NSURL URLWithString:[_address stringByAppendingString:url]]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];

    if (form) {
        form = [form stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSData *requestData = [NSData dataWithBytes:[form UTF8String] length:[form length]];
        [request setHTTPBody:requestData];
    }

    [self sendRequestAsync:request repo:repoId success:success failure:failure];
}

- (void)testConnection
{
    [self sendRequest:API_URL"/ping/" repo:nil
              success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         Debug("header=%@\n",  [response allHeaderFields]);
         NSString *logined = [[response allHeaderFields] objectForKey:@"logined"];
         if ([@"pong" caseInsensitiveCompare:JSON] == NSOrderedSame) {
             if ([logined caseInsensitiveCompare:@"true"] != NSOrderedSame)
                 _sessionid = nil;
             [self.delegate connectionEstablishingSuccess:self];
         } else {
             [self.delegate connectionEstablishingFailed:self];
         }
     }
              failure:
     ^(NSURLRequest *request, NSURLResponse *response, NSError *error, id JSON) {
         [self.delegate connectionEstablishingFailed:self];
     }];
}

- (void)loadRepos:(id)degt
{
    _rootFolder.delegate = degt;
    [_rootFolder loadContent:NO];
    [self getStarredFiles:nil failure:nil];
}

#pragma -mark starred files
- (StarredFiles *)loadCacheObj
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    NSManagedObjectContext *context = [appdelegate managedObjectContext];
    NSFetchRequest *fetchRequest=[[NSFetchRequest alloc] init];
    [fetchRequest setEntity:[NSEntityDescription entityForName:@"StarredFiles" inManagedObjectContext:context]];
    NSSortDescriptor *sortDescriptor=[[NSSortDescriptor alloc] initWithKey:@"url" ascending:YES selector:nil];
    NSArray *descriptor=[NSArray arrayWithObject:sortDescriptor];
    [fetchRequest setSortDescriptors:descriptor];

    NSString *preformat = [NSString stringWithFormat:@"url=='%@'", self.address];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:preformat]];

    NSFetchedResultsController *controller = [[NSFetchedResultsController alloc]
                                              initWithFetchRequest:fetchRequest
                                              managedObjectContext:context
                                              sectionNameKeyPath:nil
                                              cacheName:nil];
    NSError *error;
    if (![controller performFetch:&error]) {
        Debug("Fetch cache error %@",[error localizedDescription]);
        return nil;
    }
    NSArray *results = [controller fetchedObjects];
    if ([results count] == 0) {
        return nil;
    }
    return [results objectAtIndex:0];
}

- (BOOL)savetoCache:(NSString *)content
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    NSManagedObjectContext *context = [appdelegate managedObjectContext];
    StarredFiles *starfiles = [self loadCacheObj];
    if (!starfiles) {
        starfiles = (StarredFiles *)[NSEntityDescription insertNewObjectForEntityForName:@"StarredFiles" inManagedObjectContext:context];
        starfiles.url = self.address;
        starfiles.content = content;
    } else {
        starfiles.content = content;
        [context updatedObjects];
    }
    [appdelegate saveContext];
    return YES;
}

- (BOOL)handleData:(id)JSON
{
    NSMutableSet *stars = [NSMutableSet set];
    for (NSDictionary *info in JSON) {
        [stars addObject:[NSString stringWithFormat:@"%@-%@", [info objectForKey:@"repo"], [info objectForKey:@"path"]]];
    }
    _starredFiles = stars;
    return YES;
}

- (void)getStarredFiles:(void (^)(NSHTTPURLResponse *response, id JSON, NSData *data))success
                failure:(void (^)(NSHTTPURLResponse *response, NSError *error, id JSON))failure
{
    [self sendRequest:API_URL"/starredfiles/"  repo:nil
              success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         @synchronized(self) {
             Debug("Success to get starred files ...\n");
             [self handleData:JSON];
             [self savetoCache:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
             if (success)
                 success (response, JSON, data);
         }
     }
              failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
         if (failure)
             failure (response, error, JSON);
     }];
}

- (id)getCachedStarredFiles
{
    StarredFiles *starfiles = [self loadCacheObj];
    if (!starfiles)
        return nil;

    NSError *error = nil;
    NSData *data = [NSData dataWithBytes:[starfiles.content UTF8String] length:starfiles.content.length];

    id JSON = AFJSONDecode (data, &error);
    if (error) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        NSManagedObjectContext *context = [appdelegate managedObjectContext];
        [context deleteObject:starfiles];
        return nil;
    }
    return JSON;
}

- (BOOL)isStarred:(NSString *)repo path:(NSString *)path
{
    NSString *key = [NSString stringWithFormat:@"%@-%@", repo, path];
    if ([_starredFiles containsObject:key])
        return YES;
    return NO;
}

- (BOOL)setStarred:(BOOL)starred repo:(NSString *)repo path:(NSString *)path
{
    NSString *op;
    NSString *key = [NSString stringWithFormat:@"%@-%@", repo, path];
    if (starred) {
        op = @"star";
        [_starredFiles addObject:key];
    } else {
        op = @"unstar";
        [_starredFiles removeObject:key];
    }
    NSString *url = [NSString stringWithFormat:API_URL"/repos/%@/filepath/?p=%@&op=%@", repo, [path escapedUrl], op];
    [self sendPost:url repo:repo form:nil
           success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         Debug("Success to star files %@, %@\n", repo, path);
     }
           failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
         Warning("Failed to star files %@, %@\n", repo, path);
     }];
    return YES;
}

- (BOOL)repoEditable:(NSString *)repo
{
    return [[self.rootFolder getRepo:repo] editable];
}

@end
