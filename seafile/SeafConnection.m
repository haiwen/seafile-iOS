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
#import "NSData+Encryption.h"
#import "Debug.h"
#import "Utils.h"

enum {
    FLAG_LOCAL_DECRYPT = 0x1,
};

#define KEY_STARREDFILES @"STARREDFILES"
#define KEY_CONTACTS @"CONTACTS"

@interface SeafConnection ()

@property (readwrite, strong) NSString *version;
@property NSMutableSet *starredFiles;
@property NSMutableDictionary *uploadFiles;
@property NSDictionary *email2nickMap;
@end

@implementation SeafConnection
@synthesize address = _address;
@synthesize info = _info;
@synthesize token = _token;
@synthesize delegate = _delegate;
@synthesize rootFolder = _rootFolder;
@synthesize starredFiles = _starredFiles;
@synthesize seafGroups = _seafGroups;
@synthesize seafContacts = _seafContacts;


- (id)init:(NSString *)url
{
    if (self = [super init]) {
        self.address = url;
        queue = [[NSOperationQueue alloc] init];
        _rootFolder = [[SeafRepos alloc] initWithConnection:self];
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        self.version = [infoDictionary objectForKey:@"CFBundleVersion"];
        self.uploadFiles = [[NSMutableDictionary alloc] init];
        _info = [[NSMutableDictionary alloc] init];
        self.email2nickMap = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (id)initWithUrl:(NSString *)url username:(NSString *)username
{
    self = [self init:url];
    if (url) {
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        NSDictionary *ainfo = [userDefaults objectForKey:[NSString stringWithFormat:@"%@/%@", url, username]];
        if (ainfo) {
            _info = [ainfo mutableCopy];
            _token = [_info objectForKey:@"token"];
        } else {
            ainfo = [userDefaults objectForKey:url];
            if (ainfo) {
                _info = [ainfo mutableCopy];
                [userDefaults setObject:nil forKey:url];
                [userDefaults setObject:ainfo forKey:[NSString stringWithFormat:@"%@/%@", url, username]];
                [userDefaults synchronize];
            }
        }
    }
    return self;
}

-(void)setAddress:(NSString *)address
{
    if ([address hasSuffix:@"/"]) {
        _address = [address substringToIndex:address.length-1];
    } else
        _address = address;
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

- (BOOL)localDecrypt:(NSString *)repoId
{
    SeafRepo *repo = [self getRepo:repoId];
    return repo.encrypted && repo.encVersion >= 2 && repo.magic;
}

- (void)getAccountInfo:(id<SSConnectionAccountDelegate>)degt
{
    [self sendRequest:API_URL"/account/info/" repo:nil
              success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         NSDictionary *account = JSON;
         Debug("account detail:%@", account);
         [self.email2nickMap setValue:[account objectForKey:@"nickname"] forKey:self.username];
         [_info setObject:[account objectForKey:@"total"] forKey:@"total"];
         [_info setObject:[account objectForKey:@"usage"] forKey:@"usage"];
         [_info setObject:_address forKey:@"link"];
         NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
         [userDefaults setObject:_info forKey:[NSString stringWithFormat:@"%@/%@", _address, self.username]];
         [userDefaults synchronize];
         [degt getAccountInfoResult:YES connection:self];
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
                                               self.address = url;
                                               _token = [JSON objectForKey:@"token"];
                                               [_info setObject:username forKey:@"username"];
                                               [_info setObject:password forKey:@"password"];
                                               [_info setObject:_token forKey:@"token"];
                                               [_info setObject:_address forKey:@"link"];
                                               NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
                                               [userDefaults setObject:_info forKey:[NSString stringWithFormat:@"%@/%@", _address, username]];
                                               [userDefaults synchronize];
                                               [self.delegate connectionLinkingSuccess:self];
                                           }
                                           failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, NSData *data){
                                               Warning("status code=%ld, error=%@\n", (long)response.statusCode, error);
                                               [self.delegate connectionLinkingFailed:self error:(int)response.statusCode];
                                           }];
    [queue addOperation:operation];
}

- (void)sendRequestAsync:(NSMutableURLRequest *)request repo:(NSString *)repoId
                 success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data))success
                 failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure
{
    if (_token)
        [request setValue:[NSString stringWithFormat:@"Token %@", _token] forHTTPHeaderField:@"Authorization"];

    [request setTimeoutInterval:30.0f];
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
    NSString *aurl;
    if ([url hasPrefix:@"http"])
        aurl = url;
    else
        aurl = [_address stringByAppendingString:url];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:aurl]];
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
}

#pragma - Cache managerment
- (SeafCacheObj *)loadSeafCacheObj:(NSString *)key
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    NSManagedObjectContext *context = [appdelegate managedObjectContext];
    NSFetchRequest *fetchRequest=[[NSFetchRequest alloc] init];
    [fetchRequest setEntity:[NSEntityDescription entityForName:@"SeafCacheObj" inManagedObjectContext:context]];
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"url" ascending:YES selector:nil];
    NSArray *descriptor = [NSArray arrayWithObject:sortDescriptor];
    [fetchRequest setSortDescriptors:descriptor];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"url==%@ AND username==%@ AND key==%@", self.address, self.username, key]];
    NSFetchedResultsController *controller = [[NSFetchedResultsController alloc]
                                              initWithFetchRequest:fetchRequest
                                              managedObjectContext:context
                                              sectionNameKeyPath:nil
                                              cacheName:nil];
    NSError *error;
    if (![controller performFetch:&error]) {
        Warning("Fetch cache error %@",[error localizedDescription]);
        return nil;
    }
    NSArray *results = [controller fetchedObjects];
    if ([results count] == 0) {
        return nil;
    }
    return [results objectAtIndex:0];
}

- (BOOL)savetoCacheKey:(NSString *)key value:(NSString *)content
{
    SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
    NSManagedObjectContext *context = [appdelegate managedObjectContext];
    SeafCacheObj *obj = [self loadSeafCacheObj:key];
    if (!obj) {
        obj = (SeafCacheObj *)[NSEntityDescription insertNewObjectForEntityForName:@"SeafCacheObj" inManagedObjectContext:context];
        obj.key = key;
        obj.url = self.address;
        obj.content = content;
        obj.username = self.username;
    } else {
        obj.content = content;
        [context updatedObjects];
    }
    [appdelegate saveContext];
    return YES;
}

- (id)getCachedObj:(NSString *)key
{
    SeafCacheObj *obj = [self loadSeafCacheObj:key];
    if (!obj) return nil;

    NSError *error = nil;
    NSData *data = [NSData dataWithBytes:[obj.content UTF8String] length:obj.content.length];
    id JSON = [Utils JSONDecode:data error:&error];
    if (error) {
        SeafAppDelegate *appdelegate = (SeafAppDelegate *)[[UIApplication sharedApplication] delegate];
        NSManagedObjectContext *context = [appdelegate managedObjectContext];
        [context deleteObject:obj];
        JSON = nil;
    }
    return JSON;
}

- (id)getCachedStarredFiles
{
    return [self getCachedObj:KEY_STARREDFILES];
}

- (void)handleStarredData:(id)JSON
{
    NSMutableSet *stars = [NSMutableSet set];
    for (NSDictionary *info in JSON) {
        [stars addObject:[NSString stringWithFormat:@"%@-%@", [info objectForKey:@"repo"], [info objectForKey:@"path"]]];
    }
    _starredFiles = stars;
}

- (void)loadCache
{
    [self handleGroupsData:[self getCachedObj:KEY_CONTACTS] fromCache:YES];
    [self handleStarredData:[self getCachedObj:KEY_STARREDFILES]];
}

- (void)getStarredFiles:(void (^)(NSHTTPURLResponse *response, id JSON, NSData *data))success
                failure:(void (^)(NSHTTPURLResponse *response, NSError *error, id JSON))failure
{
    [self sendRequest:API_URL"/starredfiles/"  repo:nil
              success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         @synchronized(self) {
             Debug("Success to get starred files ...\n");
             [self handleStarredData:JSON];
             [self savetoCacheKey:KEY_STARREDFILES value:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
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

- (BOOL)handleGroupsData:(id)JSON fromCache:(BOOL)fromCache
{
    int msgnum = 0;
    if (!JSON) return YES;
    NSMutableArray *contacts = [[NSMutableArray alloc] init];
    NSMutableArray *groups = [[NSMutableArray alloc] init];
    if (![JSON isKindOfClass:[NSDictionary class]])
        return NO;
    for (NSDictionary *info in [JSON objectForKey:@"groups"]) {
        NSMutableDictionary *dict = [info mutableCopy];
        [dict setObject:[NSString stringWithFormat:@"%d", MSG_GROUP] forKey:@"type"];
        if (fromCache)
            [dict setObject:@"0" forKey:@"msgnum"];
        else
            msgnum += [[dict objectForKey:@"msgnum"] integerValue:0];
        [groups addObject:dict];
    }
    for (NSDictionary *info in [JSON objectForKey:@"contacts"]) {
        NSMutableDictionary *dict = [info mutableCopy];
        [dict setObject:[NSString stringWithFormat:@"%d", MSG_USER] forKey:@"type"];
        if (fromCache)
            [dict setObject:@"0" forKey:@"msgnum"];
        else
            msgnum += [[dict objectForKey:@"msgnum"] integerValue:0];
        [contacts addObject:dict];
    }
    _seafGroups = groups;
    _seafContacts = contacts;
    self.seafReplies = [[NSMutableArray alloc] init];
    if (!fromCache) {
        for (NSDictionary *info in [JSON objectForKey:@"newreplies"]) {
            NSMutableDictionary *dict = [info mutableCopy];
            [dict setObject:[NSString stringWithFormat:@"%d", MSG_REPLY] forKey:@"type"];
            NSString *title = [NSString stringWithFormat:@"New replies from %@", [dict objectForKey:@"name"]];
            [dict setObject:title forKey:@"name"];
            msgnum += [[dict objectForKey:@"msgnum"] integerValue:0];
            [self.seafReplies addObject:dict];
        }
    }
    self.newmsgnum = msgnum;
    return YES;
}

- (void)getSeafGroupAndContacts:(void (^)(NSHTTPURLResponse *response, id JSON, NSData *data))success
                        failure:(void (^)(NSHTTPURLResponse *response, NSError *error, id JSON))failure
{
    [self sendRequest:API_URL"/groupandcontacts/"  repo:nil
              success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         @synchronized(self) {
             if ([self handleGroupsData:JSON fromCache:NO]) {
                 for (NSDictionary *c in self.seafContacts) {
                     if ([c objectForKey:@"name"] && [c objectForKey:@"email"]) {
                         [self.email2nickMap setValue:[c objectForKey:@"name"] forKey:[c objectForKey:@"email"]];
                     }
                 }
                 [self savetoCacheKey:KEY_CONTACTS value:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
             }
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

- (SeafRepo *)getRepo:(NSString *)repo
{
    return [self.rootFolder getRepo:repo];
}

- (SeafUploadFile *)getUploadfile:(NSString *)lpath
{
    SeafUploadFile *ufile = [self.uploadFiles objectForKey:lpath];
    if (!ufile) {
        ufile = [[SeafUploadFile alloc] initWithPath:lpath];
        [self.uploadFiles setObject:ufile forKey:lpath];
    }
    return ufile;
}

- (void)removeUploadfile:(SeafUploadFile *)ufile
{
    [self.uploadFiles removeObjectForKey:ufile.lpath];
}

- (void)search:(NSString *)keyword
       success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSMutableArray *results))success
       failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure
{
    NSString *url = [NSString stringWithFormat:API_URL"/search/?q=%@&per_page=100", [keyword escapedUrl]];
    [self sendRequest:url repo:nil success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
        NSMutableArray *results = [[NSMutableArray alloc] init];
        for (NSDictionary *itemInfo in [JSON objectForKey:@"results"]) {
            if ([itemInfo objectForKey:@"name"] == [NSNull null]) continue;
            NSString *oid = [itemInfo objectForKey:@"oid"];
            NSString *repoId = [itemInfo objectForKey:@"repo_id"];
            NSString *name = [itemInfo objectForKey:@"name"];
            NSString *path = [itemInfo objectForKey:@"fullpath"];
            SeafFile *file = [[SeafFile alloc] initWithConnection:self oid:oid repoId:repoId name:name path:path mtime:[[itemInfo objectForKey:@"last_modified"] integerValue:0] size:[[itemInfo objectForKey:@"size"] integerValue:0]];
            [results addObject:file];
        }
        success(request, response, JSON, results);
    } failure:failure];
}

- (void)registerDevice:(NSData *)deviceToken
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDictionary objectForKey:@"CFBundleVersion"];
    NSString *platform = [infoDictionary objectForKey:@"DTPlatformName"];
    NSString *platformVersion = [infoDictionary objectForKey:@"DTPlatformVersion"];

    NSString *form = [NSString stringWithFormat:@"deviceToken=%@&version=%@&platform=%@&pversion=%@", deviceToken.hexString, version, platform, platformVersion ];
    Debug("info=%@, form=%@, len=%lu", infoDictionary, form, (unsigned long)deviceToken.length);
    [self sendPost:@"/regdevice/" repo:nil form:form success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
        Debug("Register success");
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        Warning("Failed to register device");
    }];
}

- (NSString *)nickForEmail:(NSString *)email
{
    NSString *nickname = [self.email2nickMap objectForKey:email];
    return nickname ? nickname : email;
}

- (NSString *)avatarForEmail:(NSString *)email;
{
    return [[NSBundle mainBundle] pathForResource:@"account" ofType:@"png"];
}
- (NSString *)avatarForGroup:(NSString *)gid
{
    return [[NSBundle mainBundle] pathForResource:@"group" ofType:@"png"];
}

- (void)downloadAvatars
{

}

@end
