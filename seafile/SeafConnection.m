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

#import "ExtentedString.h"
#import "Debug.h"
#import "Utils.h"

@interface SeafConnection ()

@property (readwrite, strong) NSString *version;
@property NSMutableSet *starredFiles;
@end

@implementation SeafConnection
@synthesize address = _address;
@synthesize info = _info;
@synthesize token = _token;
@synthesize delegate = _delegate;
@synthesize rootFolder = _rootFolder;
@synthesize starredFiles = _starredFiles;
@synthesize seafGroups = _seafGroups;
@synthesize version;

- (id)init:(NSString *)url
{
    if (self = [super init]) {
        _address = url;
        queue = [[NSOperationQueue alloc] init];
        _rootFolder = [[SeafRepos alloc] initWithConnection:self];
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        version = [infoDictionary objectForKey:@"CFBundleVersion"];
    }
    return self;
}

- (id)initWithUrl:(NSString *)url username:(NSString *)username
{
    self = [self init:url];
    if (!url) {
        _info = [[NSMutableDictionary alloc] init];
    } else {
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        NSDictionary *ainfo = [userDefaults objectForKey:url];
        if (ainfo) {
            _info = [ainfo mutableCopy];
            _token = [_info objectForKey:@"token"];
        } else {
            _info = [[NSMutableDictionary alloc] init];
        }
    }
    return self;
}

- (NSString *)username
{
    return [_info objectForKey:@"username"];
}

- (NSString *)password
{
    return [_info objectForKey:@"password"];
}

- (long long)quota
{
    return [[_info objectForKey:@"total"] integerValue:0];
}

- (long long)usage
{
    return [[_info objectForKey:@"usage"] integerValue:-1];
}

- (void)getAccountInfo:(id<SSConnectionAccountDelegate>)degt
{
    [self sendRequest:API_URL"/account/info/" repo:nil
              success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         NSDictionary *account = JSON;
         [_info setObject:[account objectForKey:@"total"] forKey:@"total"];
         [_info setObject:[account objectForKey:@"usage"] forKey:@"usage"];
         [_info setObject:_address forKey:@"link"];
         NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
         [userDefaults setObject:_info forKey:_address];
         [userDefaults synchronize];         [degt getAccountInfoResult:YES connection:self];
     }
              failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
         [degt getAccountInfoResult:NO connection:self];
     }];
}


/*
 curl -D a.txt --data "username=pithier@163.com&password=pithier" http://www.gonggeng.org/seahub/api2/auth-token/
 */
- (void)loginWithAddress:(NSString *)anAddress username:(NSString *)username password:(NSString *)password
{
    NSString *url = _address;
    if (anAddress)
        url = anAddress;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[url stringByAppendingString:API_URL"/auth-token/"]]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSString *formString = [NSString stringWithFormat:@"username=%@&password=%@", [username escapedPostForm], [password escapedPostForm]];
    [request setHTTPBody:[NSData dataWithBytes:[formString UTF8String] length:[formString length]]];
    SeafJSONRequestOperation *operation = [SeafJSONRequestOperation
                                           JSONRequestOperationWithRequest:request
                                           success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
                                               _address = url;
                                               _token = [JSON objectForKey:@"token"];
                                               [_info setObject:username forKey:@"username"];
                                               [_info setObject:password forKey:@"password"];
                                               [_info setObject:_token forKey:@"token"];
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
    if (_token)
        [request setValue:[NSString stringWithFormat:@"Token %@", _token] forHTTPHeaderField:@"Authorization"];

    if (repoId) {
        password = [Utils getRepoPassword:repoId];
        if (password) {
            [request setValue:password forHTTPHeaderField:@"password"];
        }
    }
    [request setValue:[NSString stringWithFormat:@"iOS Client v%@", version] forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"iOS Client" forHTTPHeaderField:@"User-Agent"];

    Debug("requestUrl=%@, token=%@, password=%@\n", request.URL, _token, password);

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
    [request setHTTPMethod:@"GET"];
    [self sendRequestAsync:request repo:repoId success:success failure:failure];
}

- (void)sendDelete:(NSString *)url repo:(NSString *)repoId
           success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data))success
           failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[_address stringByAppendingString:url]]];
    [request setHTTPMethod:@"DELETE"];
    [self sendRequestAsync:request repo:repoId success:success failure:failure];
}

- (void)sendPut:(NSString *)url repo:(NSString *)repoId form:(NSString *)form
        success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data))success
        failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure;
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[_address stringByAppendingString:url]]];
    [request setHTTPMethod:@"PUT"];
    [request setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];

    if (form) {
        NSData *requestData = [NSData dataWithBytes:[form UTF8String] length:[form length]];
        [request setHTTPBody:requestData];
    }
    [self sendRequestAsync:request repo:repoId success:success failure:failure];
}

- (void)sendPost:(NSString *)url repo:(NSString *)repoId form:(NSString *)form
         success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data))success
         failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[_address stringByAppendingString:url]]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];

    if (form) {
        NSData *requestData = [NSData dataWithBytes:[form UTF8String] length:[form length]];
        [request setHTTPBody:requestData];
    }

    [self sendRequestAsync:request repo:repoId success:success failure:failure];
}

- (void)loadRepos:(id)degt
{
    _rootFolder.delegate = degt;
    [_rootFolder loadContent:NO];
    [self handleGroupsData:[self getCachedGroups]];
    [self getStarredFiles:nil failure:nil];
}

#pragma -mark starred files
- (id)loadCacheObj:(NSString *)name
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    NSManagedObjectContext *context = [appdelegate managedObjectContext];
    NSFetchRequest *fetchRequest=[[NSFetchRequest alloc] init];
    [fetchRequest setEntity:[NSEntityDescription entityForName:name inManagedObjectContext:context]];
    NSSortDescriptor *sortDescriptor=[[NSSortDescriptor alloc] initWithKey:@"url" ascending:YES selector:nil];
    NSArray *descriptor=[NSArray arrayWithObject:sortDescriptor];
    [fetchRequest setSortDescriptors:descriptor];

    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"url==%@ AND username==%@", self.address, self.username]];

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

- (BOOL)saveStarstoCache:(NSString *)content
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    NSManagedObjectContext *context = [appdelegate managedObjectContext];
    StarredFiles *starfiles = [self loadCacheObj:@"StarredFiles"];
    if (!starfiles) {
        starfiles = (StarredFiles *)[NSEntityDescription insertNewObjectForEntityForName:@"StarredFiles" inManagedObjectContext:context];
        starfiles.url = self.address;
        starfiles.content = content;
        starfiles.username = self.username;
    } else {
        starfiles.content = content;
        [context updatedObjects];
    }
    [appdelegate saveContext];
    return YES;
}

- (BOOL)saveGroupstoCache:(NSString *)content
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    NSManagedObjectContext *context = [appdelegate managedObjectContext];
    SeafGroups *groups = [self loadCacheObj:@"SeafGroups"];
    if (!groups) {
        groups = (SeafGroups *)[NSEntityDescription insertNewObjectForEntityForName:@"SeafGroups" inManagedObjectContext:context];
        groups.url = self.address;
        groups.content = content;
        groups.username = self.username;
    } else {
        groups.content = content;
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
             [self saveStarstoCache:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
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
    StarredFiles *starfiles = [self loadCacheObj:@"StarredFiles"];
    if (!starfiles)
        return nil;

    NSError *error = nil;
    NSData *data = [NSData dataWithBytes:[starfiles.content UTF8String] length:starfiles.content.length];

    id JSON = [Utils JSONDecode:data error:&error];
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
    NSString *key = [NSString stringWithFormat:@"%@-%@", repo, path];
    if (starred) {
        [_starredFiles addObject:key];
        NSString *form = [NSString stringWithFormat:@"repo_id=%@&p=%@", repo, [path escapedUrl]];
        NSString *url = [NSString stringWithFormat:API_URL"/starredfiles/"];
        [self sendPost:url repo:repo form:form
               success:
         ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
             Debug("Success to star file %@, %@\n", repo, path);
         }
               failure:
         ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
             Warning("Failed to star file %@, %@\n", repo, path);
         }];
    } else {
        [_starredFiles removeObject:key];
        NSString *url = [NSString stringWithFormat:API_URL"/starredfiles/?repo_id=%@&p=%@", repo, path.escapedUrl];
        [self sendDelete:url repo:repo
               success:
         ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
             Debug("Success to unstar file %@, %@\n", repo, path);
         }
               failure:
         ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
             Warning("Failed to unstar file %@, %@\n", repo, path);
         }];
    }

    return YES;
}

- (BOOL)handleGroupsData:(id)JSON
{
    NSMutableArray *groups = [[NSMutableArray alloc] init];
    for (NSDictionary *info in JSON) {
        [groups addObject:info];
    }
    _seafGroups = groups;
    return YES;
}

- (void)getSeafGroups:(void (^)(NSHTTPURLResponse *response, id JSON, NSData *data))success
              failure:(void (^)(NSHTTPURLResponse *response, NSError *error, id JSON))failure
{
    [self sendRequest:API_URL"/groups/"  repo:nil
              success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         @synchronized(self) {
             Debug("Success to get groups ...%@\n", JSON);
             [self handleGroupsData:JSON];
             [self saveGroupstoCache:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
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

- (id)getCachedGroups
{
    SeafGroups *groups = [self loadCacheObj:@"SeafGroups"];
    if (!groups)
        return nil;
    
    NSError *error = nil;
    NSData *data = [NSData dataWithBytes:[groups.content UTF8String] length:groups.content.length];
    
    id JSON = [Utils JSONDecode:data error:&error];
    if (error) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        NSManagedObjectContext *context = [appdelegate managedObjectContext];
        [context deleteObject:groups];
        return nil;
    }
    return JSON;
}

- (BOOL)repoEditable:(NSString *)repo
{
    return [[self.rootFolder getRepo:repo] editable];
}

@end
