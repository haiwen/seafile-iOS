//
//  SeafDir.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafData.h"
#import "SeafDir.h"
#import "SeafRepos.h"

#import "SeafFile.h"
#import "SeafUploadFile.h"
#import "SeafGlobal.h"

#import "ExtentedString.h"
#import "Utils.h"
#import "Debug.h"


static NSComparator CMP = ^(id obj1, id obj2) {
    if (([obj1 class] == [SeafDir class]) && ([obj2 class] == [SeafDir class])) {
        return [[(SeafDir *)obj1 name] caseInsensitiveCompare:[(SeafDir *)obj2 name]];
    } else if (([obj1 class] == [SeafDir class]) || ([obj2 class] == [SeafDir class])) {
        if ([obj1 isKindOfClass:[SeafDir class]]) {
            return NSOrderedAscending;
        } else {
            return NSOrderedDescending;
        }
    } else {
        if ([obj1 conformsToProtocol:@protocol(SeafPreView)] && [obj2 conformsToProtocol:@protocol(SeafPreView)]) {
            return [SeafGlobal.sharedObject compare:obj1 with:obj2];
        }
    }
    return NSOrderedSame;
};

@interface SeafDir ()

@end

@implementation SeafDir
@synthesize items = _items;
@synthesize uploadItems = _uploadItems;
@synthesize allItems = _allItems;


- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    name:(NSString *)aName
                    path:(NSString *)aPath
{
    self = [super initWithConnection:aConnection oid:anId repoId:aRepoId name:aName path:aPath mime:@"text/directory"];
    return self;
}

- (BOOL)editable
{
    return [[connection getRepo:self.repoId] editable];
}

- (BOOL)handleData:(NSString *)oid data:(id)JSON
{
    @synchronized(self) {
        if (oid) {
            if ([oid isEqualToString:self.ooid])
                return NO;
            self.ooid = oid;
        } else {
            if ([@"uptodate" isEqual:JSON])
                return NO;
        }
    }

    NSMutableArray *newItems = [NSMutableArray array];
    for (NSDictionary *itemInfo in JSON) {
        if ([itemInfo objectForKey:@"name"] == [NSNull null])
            continue;
        SeafBase *newItem = nil;
        NSString *type = [itemInfo objectForKey:@"type"];
        NSString *name = [itemInfo objectForKey:@"name"];
        NSString *path = [self.path isEqualToString:@"/"] ? [NSString stringWithFormat:@"/%@", name]:[NSString stringWithFormat:@"%@/%@", self.path, name];

        if ([type isEqual:@"file"]) {
            newItem = [[SeafFile alloc] initWithConnection:connection oid:[itemInfo objectForKey:@"id"] repoId:self.repoId name:name path:path mtime:[[itemInfo objectForKey:@"mtime"] integerValue:0] size:[[itemInfo objectForKey:@"size"] integerValue:0]];
        } else if ([type isEqual:@"dir"]) {
            newItem = [[SeafDir alloc] initWithConnection:connection oid:[itemInfo objectForKey:@"id"] repoId:self.repoId name:name path:path];
        }
        [newItems addObject:newItem];
    }
    [self loadedItems:newItems];
    return YES;
}

- (void)handleResponse:(NSHTTPURLResponse *)response json:(id)JSON
{
    [self checkUploadFiles];
    @synchronized(self) {
        self.state = SEAF_DENTRY_UPTODATE;
        NSString *curId = [[response allHeaderFields] objectForKey:@"oid"];
        if (!curId) curId = self.oid;
        if ([self handleData:curId data:JSON]) {
            self.ooid = curId;
            NSData *data = [Utils JSONEncode:JSON];
            [self savetoCache:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
            [self.delegate entry:self updated:true progress:100];
        } else {
            Debug("Already uptodate oid=%@\n", self.ooid);
            self.state = SEAF_DENTRY_UPTODATE;
            [self.delegate entry:self updated:NO progress:0];
        }
        if (![self.oid isEqualToString:curId]) {
            self.oid = curId;
        }
    }
}

- (NSString *)url
{
    NSString *requestStr = [NSString stringWithFormat:API_URL"/repos/%@/dir/?p=%@", self.repoId, [self.path escapedUrl]];
    if (self.ooid)
        requestStr = [requestStr stringByAppendingFormat:@"&oid=%@", self.ooid ];

    return requestStr;
}

/*
 curl -D a.txt -H 'Cookie:sessionid=7eb567868b5df5b22b2ba2440854589c' http://127.0.0.1:8000/api/dir/640fd90d-ef4e-490d-be1c-b34c24040da7/?p=/SSD-FTL

 [{"id": "0d6a4cc4e084fec6cde0f50d628cf4f502ced622", "type": "file", "name": "shin_SSD.pdf", "size": 1092236}, {"id": "2ac5dfb7126bea3a2038069688337bd3f64e80e2", "type": "file", "name": "FTL design exploration in reconfigurable high-performance SSD for server applications.pdf", "size": 675464}, {"id": "eee56009908153baf5cf21615cea00cba657cb0a", "type": "file", "name": "DFTL.pdf", "size": 1232088}, {"id": "97eb7fd4f9ad45c821ed3ddd662c5d2b27ab7e45", "type": "file", "name": "BPLRU a buffer management scheme for improving random writes in flash storage.pdf", "size": 1113100}, {"id": "1578adbc33c143f68c5a79b421f1d9d7f0d52bc8", "type": "file", "name": "Algorithms and Data Structures for Flash Memories.pdf", "size": 689915}, {"id": "8dd0a3be9289aea6795c1203351691fcc1373fbb", "type": "file", "name": "2006-Intel TR-Understanding the flash translation layer (FTL)specification.pdf", "size": 84054}]
 */
- (void)downloadContentSuccess:(void (^)(SeafDir *dir)) success failure:(void (^)(SeafDir *dir))failure
{
    [connection sendRequest:self.url
                    success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
                        [self handleResponse:response json:JSON];
                        if (success)
                            success(self);
                    }
                    failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
                        self.state = SEAF_DENTRY_INIT;
                        if (failure)
                            failure(self);
                        [self.delegate entry:self downloadingFailed:response.statusCode];
                    }];
}

- (void)realLoadContent
{
    [self downloadContentSuccess:nil failure:nil];
}

- (void)updateItems:(NSMutableArray *)items
{
    int i = 0;
    if (!_items)
        _items = items;
    else {
        NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
        for (i = 0; i < [_items count]; ++i) {
            SeafBase *obj = (SeafBase*)[_items objectAtIndex:i];
            [dict setObject:obj forKey:[obj key]];
        }
        for (i = 0; i < [items count]; ++i) {
            SeafBase *obj = (SeafBase*)[items objectAtIndex:i];
            SeafBase *oldObj = [dict objectForKey:[obj key]];
            if (oldObj && [obj class] == [oldObj class]) {
                [oldObj updateWithEntry:obj];
                [items replaceObjectAtIndex:i withObject:oldObj];
            }
        }
        _items = items;
    }
    _allItems = nil;
}

- (BOOL)checkSorted:(NSArray *)items
{
    int i;
    for (i = 1; i < [items count]; ++i) {
        id obj1 = (SeafBase*)[items objectAtIndex:i-1];
        id obj2 = (SeafBase*)[items objectAtIndex:i];
        if (CMP(obj1, obj2) == NSOrderedDescending)
            return NO;
    }
    return YES;
}

- (void)sortItems:(NSMutableArray *)items
{
    if ([self checkSorted:items] == NO) {
        [items sortUsingComparator:CMP];
    }
}

- (void)reSortItems
{
    _allItems = nil;
    [self sortItems:_items];
}

- (void)loadedItems:(NSMutableArray *)items
{
    [self sortItems:items];
    [self updateItems:items];
}

- (void)clearCache
{
    NSManagedObjectContext *context = [[SeafGlobal sharedObject] managedObjectContext];
    Directory *dir = [self loadCacheObj];
    if (dir) {
        Debug("Delete directory %@ cache.", self.path);
        [context deleteObject:dir];
        [[SeafGlobal sharedObject] saveContext];
    }
}

- (Directory *)loadCacheObj
{
    NSManagedObjectContext *context = [[SeafGlobal sharedObject] managedObjectContext];
    NSFetchRequest *fetchRequest=[[NSFetchRequest alloc] init];
    [fetchRequest setEntity:[NSEntityDescription entityForName:@"Directory"
                                        inManagedObjectContext:context]];
    NSSortDescriptor *sortDescriptor=[[NSSortDescriptor alloc] initWithKey:@"path" ascending:YES selector:nil];
    NSArray *descriptor = [NSArray arrayWithObject:sortDescriptor];
    [fetchRequest setSortDescriptors:descriptor];

    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"repoid==%@ AND path==%@", self.repoId, self.path]];

    NSFetchedResultsController *controller = [[NSFetchedResultsController alloc]
                                              initWithFetchRequest:fetchRequest
                                              managedObjectContext:context
                                              sectionNameKeyPath:nil
                                              cacheName:nil];
    NSError *error;
    if (![controller performFetch:&error]) {
        Debug(@"Fetch cache error:%@",[error localizedDescription]);
        return nil;
    }
    NSArray *results = [controller fetchedObjects];
    if ([results count] == 0)
        return nil;
    Directory *dir = [results objectAtIndex:0];
    return dir;
}

- (BOOL)savetoCache:(NSString *)content
{
    NSManagedObjectContext *context = [[SeafGlobal sharedObject] managedObjectContext];
    Directory *dir = [self loadCacheObj];
    if (!dir) {
        dir = (Directory *)[NSEntityDescription insertNewObjectForEntityForName:@"Directory" inManagedObjectContext:context];
        dir.oid = self.ooid;
        dir.repoid = self.repoId;
        dir.content = content;
        dir.path = self.path;
    } else {
        dir.oid = self.ooid;
        dir.content = content;
    }
    [[SeafGlobal sharedObject] saveContext];
    return YES;
}

- (BOOL)realLoadCache
{
    NSError *error = nil;
    Directory *dir = [self loadCacheObj];
    if (!dir)
        return NO;
    NSData *data = [NSData dataWithBytes:dir.content.UTF8String length:[dir.content lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
    id JSON = [Utils JSONDecode:data error:&error];
    if (error) {
        NSManagedObjectContext *context = [[SeafGlobal sharedObject] managedObjectContext];
        [context deleteObject:dir];
        return NO;
    }

    BOOL updated = [self handleData:dir.oid data:JSON];
    [self.delegate entry:self updated:updated progress:100];
    return YES;
}

- (void)mkdir:(NSString *)newDirName
{
    [self mkdir:newDirName success:nil failure:nil];
}

- (void)mkdir:(NSString *)newDirName success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir))failure
{
    NSString *path = [self.path stringByAppendingPathComponent:newDirName];
    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/dir/?p=%@&reloaddir=true", self.repoId, [path escapedUrl]];

    [connection sendPost:requestUrl form:@"operation=mkdir"
                 success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         Debug("resp=%ld\n", (long)response.statusCode);
         [self handleResponse:response json:JSON];
         if (success) success(self);
     }
                 failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
         Warning("resp=%ld\n", (long)response.statusCode);
         [self.delegate entry:self downloadingFailed:response.statusCode];
         if (failure) failure(self);
     }];
}

- (void)createFile:(NSString *)newFileName
{
    NSString *path = [self.path stringByAppendingPathComponent:newFileName];
    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@&reloaddir=true", self.repoId, [path escapedUrl]];

    [connection sendPost:requestUrl form:@"operation=create"
                 success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         Debug("resp=%ld\n", (long)response.statusCode);
         [self handleResponse:response json:JSON];
     }
                 failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
         Warning("resp=%ld\n", (long)response.statusCode);
         [self.delegate entry:self downloadingFailed:response.statusCode];
     }];
}

- (void)delEntries:(NSArray *)entries
{
    int i = 0;
    NSAssert(entries.count > 0, @"There must be at least one entry");
    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/fileops/delete/?p=%@&reloaddir=true", self.repoId, [self.path escapedUrl]];

    NSMutableString *form = [[NSMutableString alloc] init];
    [form appendFormat:@"file_names=%@", [[[entries objectAtIndex:0] name] escapedPostForm]];

    for (i = 1; i < entries.count; ++i) {
        SeafBase *entry = [entries objectAtIndex:i];
        [form appendFormat:@":%@", [entry.name escapedPostForm]];
    }

    [connection sendPost:requestUrl form:form
                 success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         Debug("resp=%ld\n", (long)response.statusCode);
         [self handleResponse:response json:JSON];
         for (int i = 0; i < entries.count; ++i) {
             SeafBase *entry = [entries objectAtIndex:i];
             [entry clearCache];
         }
     }
                 failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
         Warning("resp=%ld\n", (long)response.statusCode);
         [self.delegate entry:self downloadingFailed:response.statusCode];
     }];
}

- (NSMutableArray *)allItems
{
    if (_allItems)
        return _allItems;

    _allItems = [[NSMutableArray alloc] init];
    [_allItems addObjectsFromArray:_items];
    [_allItems addObjectsFromArray:self.uploadItems];
    if ([self checkSorted:_allItems] == NO) {
        [_allItems sortUsingComparator:CMP];
    }
    return _allItems;
}

- (void)loadContent:(BOOL)force;
{
    _allItems = nil;
    [super loadContent:force];
}

- (NSMutableArray *)uploadItems
{
    if (self.path && !_uploadItems)
        _uploadItems = [SeafUploadFile uploadFilesForDir:self];

    if (!_uploadItems)
        _uploadItems = [[NSMutableArray alloc] init];
    return _uploadItems;
}

- (void)addUploadFile:(SeafUploadFile *)file flush:(BOOL)flush;
{
    if ([self.uploadItems containsObject:file]) return;
    NSMutableDictionary *dict = file.uploadAttr;
    if (!dict)
        dict = [[NSMutableDictionary alloc] init];
    [dict setObject:self.repoId forKey:@"urepo"];
    [dict setObject:self.path forKey:@"upath"];
    [dict setObject:[NSNumber numberWithBool:file.update] forKey:@"update"];
    [dict setObject:[NSNumber numberWithBool:file.autoSync] forKey:@"autoSync"];
    if (file.asset) {
        [dict setObject:file.asset.defaultRepresentation.url.absoluteString forKey:@"assetURL"];
    }
    file.udir = self;
    [file saveAttr:dict flush:flush];
    [self.uploadItems addObject:file];
    _allItems = nil;
    [self.delegate entry:self updated:true progress:100];
}

- (void)checkUploadFiles
{
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    for (SeafUploadFile *file in self.uploadItems) {
        NSMutableDictionary *dict = file.uploadAttr;
        if (dict) {
            BOOL result = [[dict objectForKey:@"result"] boolValue];
            if (result) {
                [arr addObject:file];
            }
        }
    }
    for (SeafUploadFile *file in arr) {
        [self removeUploadFile:file];
    }
}

- (void)removeUploadFile:(SeafUploadFile *)ufile
{
    [SeafGlobal.sharedObject removeBackgroundUpload:ufile];
    [connection removeUploadfile:ufile];
    [ufile doRemove];
    [self.uploadItems removeObject:ufile];
    _allItems = nil;
}

- (void)renameFile:(SeafFile *)sfile newName:(NSString *)newName
{
    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@&reloaddir=true", self.repoId, [sfile.path escapedUrl]];
    NSString *form = [NSString stringWithFormat:@"operation=rename&newname=%@", [newName escapedUrl]];
    [connection sendPost:requestUrl form:form
                 success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         Debug("resp=%ld\n", (long)response.statusCode);
         [self handleResponse:response json:JSON];
     }
                 failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
         Warning("resp=%ld\n", (long)response.statusCode);
         [self.delegate entry:self downloadingFailed:response.statusCode];
     }];
}

- (void)copyEntries:(NSArray *)entries dstDir:(SeafDir *)dir
{
    int i = 0;
    NSAssert(entries.count > 0, @"There must be at least one entry");
    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/fileops/copy/?p=%@&reloaddir=true", self.repoId, [self.path escapedUrl]];

    NSMutableString *form = [[NSMutableString alloc] init];
    [form appendFormat:@"dst_repo=%@&dst_dir=%@&file_names=%@", dir.repoId, [dir.path escapedUrl], [[[entries objectAtIndex:0] name] escapedPostForm]];

    for (i = 1; i < entries.count; ++i) {
        SeafBase *entry = [entries objectAtIndex:i];
        [form appendFormat:@":%@", [entry.name escapedPostForm]];
    }

    [connection sendPost:requestUrl form:form
                 success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         Debug("resp=%ld\n", (long)response.statusCode);
         [self handleResponse:response json:JSON];
     }
                 failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
         Warning("resp=%ld\n", (long)response.statusCode);
         [self.delegate entry:self downloadingFailed:response.statusCode];
     }];
}

- (void)moveEntries:(NSArray *)entries dstDir:(SeafDir *)dir
{
    int i = 0;
    NSAssert(entries.count > 0, @"There must be at least one entry");
    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/fileops/move/?p=%@&reloaddir=true", self.repoId, [self.path escapedUrl]];

    NSMutableString *form = [[NSMutableString alloc] init];
    [form appendFormat:@"dst_repo=%@&dst_dir=%@&file_names=%@", dir.repoId, [dir.path escapedUrl], [[[entries objectAtIndex:0] name] escapedPostForm]];

    for (i = 1; i < entries.count; ++i) {
        SeafBase *entry = [entries objectAtIndex:i];
        [form appendFormat:@":%@", [entry.name escapedPostForm]];
    }

    [connection sendPost:requestUrl form:form
                 success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         Debug("resp=%ld\n", (long)response.statusCode);
         [self handleResponse:response json:JSON];
     }
                 failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
         Warning("resp=%ld\n", (long)response.statusCode);
         [self.delegate entry:self downloadingFailed:response.statusCode];
     }];
}

- (void)generateShareLink:(id<SeafShareDelegate>)dg
{
    return [self generateShareLink:dg type:@"d"];
}

@end
