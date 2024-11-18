//
//  SeafDir.m
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafDir.h"
#import "SeafRepos.h"
#import "SeafStorage.h"

#import "SeafFile.h"
#import "SeafUploadFile.h"
#import "SeafDataTaskManager.h"
#import "SeafAccountTaskQueue.h"

#import "ExtentedString.h"
#import "Utils.h"
#import "Debug.h"
#import "SeafUploadOperation.h"

typedef NSComparisonResult (^SeafSortableCmp)(id<SeafSortable> obj1, id<SeafSortable> obj2);

typedef NSComparisonResult (^SeafCmpFunc)(id obj1, id obj2, SeafSortableCmp comparator);

static SeafCmpFunc seafCmpFunc = ^(id obj1, id obj2, SeafSortableCmp comparator) {
    if ([obj1 conformsToProtocol:@protocol(SeafSortable)] && [obj2 conformsToProtocol:@protocol(SeafSortable)]) {
        return comparator((id<SeafSortable>)obj1, (id<SeafSortable>)obj2);
    } else if ([obj1 isKindOfClass:[SeafDir class]] && [obj2 isKindOfClass:[SeafDir class]]) {
        return [[(SeafDir *)obj1 name] caseInsensitiveCompare:[(SeafDir *)obj2 name]];
    } else if ([obj1 isKindOfClass:[SeafDir class]] || [obj2 isKindOfClass:[SeafDir class]]) {
        if ([obj1 isKindOfClass:[SeafDir class]]) {
            return NSOrderedAscending;
        } else {
            return NSOrderedDescending;
        }
    }
    return NSOrderedSame;
};


static NSComparator seafSortByName = ^(id a, id b) {
    return seafCmpFunc(a, b, ^(id<SeafSortable> obj1, id<SeafSortable> obj2) {
        return [obj1.name caseInsensitiveCompare:obj2.name];
    });
};

static NSComparator seafSortByMtime = ^(id a, id b) {
    return seafCmpFunc(a, b, ^(id<SeafSortable> obj1, id<SeafSortable> obj2) {
        return [[NSNumber numberWithLongLong:obj2.mtime] compare:[NSNumber numberWithLongLong:obj1.mtime]];
    });
};


@interface SeafDir ()
@property NSObject *uploadLock;
@property (readonly, nonatomic) NSMutableArray *uploadItems;//Files being uploaded in the current directory.

@end

@implementation SeafDir
@synthesize items = _items;
@synthesize uploadItems = _uploadItems;
@synthesize allItems = _allItems;


- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    perm:(NSString *)aPerm
                    name:(NSString *)aName
                    path:(NSString *)aPath
{
    NSString *aMime = @"text/directory";
    if ([aPerm.lowercaseString isEqualToString:@"r"]) {
        aMime = @"text/directory-readonly";
    }
    return [self initWithConnection:aConnection oid:anId repoId:aRepoId perm:aPerm name:aName path:aPath mime:aMime];
}

- (id)initWithConnection:(SeafConnection *)aConnection
                     oid:(NSString *)anId
                  repoId:(NSString *)aRepoId
                    perm:(NSString *)aPerm
                    name:(NSString *)aName
                    path:(NSString *)aPath
                    mime:(NSString *)aMime
{
    self = [super initWithConnection:aConnection oid:anId repoId:aRepoId name:aName path:aPath mime:aMime];
    _uploadLock = [[NSObject alloc] init];
    _perm = aPerm;
    return self;
}

- (BOOL)editable
{
    if (self.perm && [self.perm isKindOfClass:[NSString class]])
        return [self.perm.lowercaseString isEqualToString:@"rw"];
    return NO;
}

- (void)unload
{
    self.ooid = nil;
    _items = nil;
    _allItems = nil;
    _uploadItems = nil;
    self.state = SEAF_DENTRY_INIT;
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
    if (![JSON isKindOfClass:[NSArray class]]) {
        Warning("Invalid response type: %@,  %@", NSStringFromClass([JSON class]), JSON);
        return false;
    }
    
    //check if has edited file not uploaded before.
    SeafAccountTaskQueue *accountQueue = [SeafDataTaskManager.sharedObject accountQueueForConnection:self->connection];
    NSArray *allUpLoadTasks = [accountQueue getNeedUploadTasks];
    
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
            SeafRepo *repo = [connection getRepo:self.repoId];
            if ([self.name isEqualToString:repo.name]) {
                newItem.fullPath = [NSString stringWithFormat:@"/%@", self.name];
            } else {
                newItem.fullPath = [NSString stringWithFormat:@"/%@/%@",repo.name,self.name];
            }
            
            NSNumber *mtimeNumber = [itemInfo objectForKey:@"mtime"];

            //create oid by 'timeStr' 'repoId' 'path'
            NSString *oid = [Utils getNewOidFromMtime:[mtimeNumber longLongValue] repoId:self.repoId path:path];
            
            newItem.oid = oid;
            if (allUpLoadTasks.count > 0) {//if have uploadTask
                for (SeafUploadFile *file in allUpLoadTasks) {
                    //check and set uploadFile to SeafFile
//                    SeafUploadFile *file = uploadOperation.uploadFile;
                    if ((file.editedFileOid != nil) && [file.editedFileOid isEqualToString:oid]) {
                        SeafFile *fileItem = (SeafFile *)newItem;
                        fileItem.ufile = file;
                        [fileItem setMpath:file.lpath];
                        fileItem.ufile.delegate = fileItem;
                        newItem = fileItem;
                    }
                }
            }
            
        } else if ([type isEqual:@"dir"]) {
            newItem = [[SeafDir alloc] initWithConnection:connection oid:[itemInfo objectForKey:@"id"] repoId:self.repoId perm:[itemInfo objectForKey:@"permission"] name:name path:path];
        }
        [newItems addObject:newItem];
    }
    [self loadedItems:newItems];
    return YES;
}

- (void)handleResponse:(NSHTTPURLResponse *)response json:(id)JSON
{
    @synchronized(self) {
        self.state = SEAF_DENTRY_UPTODATE;
        NSString *curId = [[response allHeaderFields] objectForKey:@"oid"];
        if (!curId) curId = self.oid;
        if ([self handleData:curId data:JSON]) {
            self.ooid = curId;
            NSString *dirPerm = [[response allHeaderFields] objectForKey:@"dir_perm"];
            if (dirPerm) {
                self.perm = dirPerm;
            }
            [self savetoCache:JSON cacheOid:curId perm:dirPerm];
            [self.delegate download:self complete:true];
        } else {
            Debug("Already uptodate oid=%@, path=%@\n", self.ooid, self.path);
            self.state = SEAF_DENTRY_UPTODATE;
            [self.delegate download:self complete:false];
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
- (void)loadContentSuccess:(void (^)(SeafDir *dir)) success failure:(void (^)(SeafDir *dir, NSError *error))failure
{
    [connection sendRequest:self.url
                    success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
                        // Force reload uplaodItems from task queue.
                        _uploadItems = nil;
                        [self handleResponse:response json:JSON];
                        if (success)  success(self);
                    }
                    failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
                        self.state = SEAF_DENTRY_INIT;
                        if (failure) failure(self, error);
                        [self.delegate download:self failed:error];
                    }];
}

- (void)realLoadContent
{
    [self loadContentSuccess:nil failure:nil];
}

- (void)updateItems:(NSMutableArray *)items
{
    int i = 0;
    if (!_items)
        _items = items;
    else {
        NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
        for (SeafBase *obj in _items) {
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
    NSComparator cmp = [self getCmpFunc];
    int i;
    for (i = 1; i < [items count]; ++i) {
        id obj1 = [items objectAtIndex:i-1];
        id obj2 = [items objectAtIndex:i];
        if (cmp(obj1, obj2) == NSOrderedDescending)
            return NO;
    }
    return YES;
}

- (void)sortItems:(NSMutableArray *)items
{
    if ([self checkSorted:items] == NO) {
        @try {
            [items sortUsingComparator:[self getCmpFunc]];
        }
        @catch (NSException *exception) {
        }
        @finally {
        }
    }
}

- (NSString *)configKeyForSort
{
    return @"SORT_KEY_FILE";
}

- (void)saveSortKey:(NSString *)keyName
{
    NSString *confKey = [self configKeyForSort];
    [SeafStorage.sharedObject setObject:keyName forKey:confKey];
}

- (void)reSortItemsByName
{
    [self saveSortKey:@"NAME"];
     _allItems = nil;
}

- (void)reSortItemsByMtime
{
    [self saveSortKey:@"MTIME"];
     _allItems = nil;
}

- (NSComparator)getCmpFunc
{
    NSString *confKey = [self configKeyForSort];
    NSString *key = [SeafStorage.sharedObject objectForKey:confKey];
    if ([@"MTIME" caseInsensitiveCompare:key] == NSOrderedSame) {
        return seafSortByMtime;
    }
    return seafSortByName;
}

- (void)loadedItems:(NSMutableArray *)items
{
    [self updateItems:items];
}

- (void)clearCache
{
    self.state = SEAF_DENTRY_INIT;
    _items = nil;
    _allItems = nil;
    [self->connection removeKey:self.cacheKey entityName:ENTITY_DIRECTORY];
}

- (BOOL)savetoCache:(id)JSON cacheOid:(NSString *)cacheOid perm:(NSString *)permStr
{
    NSMutableDictionary *dict = [NSMutableDictionary new];
    [dict setObject:JSON forKey:@"data"];
    [dict setObject:cacheOid forKey:@"oid"];
    [dict setObject:permStr forKey:@"perm"];

    NSString *value = [[NSString alloc] initWithData:[Utils JSONEncode:dict] encoding:NSUTF8StringEncoding];
    return [self->connection setValue:value forKey:self.cacheKey entityName:ENTITY_DIRECTORY];
}

- (BOOL)realLoadCache
{
    NSDictionary *dict = [self->connection getCachedJson:self.cacheKey entityName:ENTITY_DIRECTORY];
    if (!dict) {
        return NO;
    }
    NSString *oid = [dict objectForKey:@"oid"];
    NSString *perm = [dict objectForKey:@"perm"];
    self.perm = perm;
    BOOL updated = [self handleData:oid data:[dict objectForKey:@"data"]];
    [self.delegate download:self complete:updated];
    return YES;
}

- (void)mkdir:(NSString *)newDirName
{
    [self mkdir:newDirName success:nil failure:nil];
}

- (void)mkdir:(NSString *)newDirName success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure
{
    NSString *path = [self.path stringByAppendingPathComponent:newDirName];
    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/dir/?p=%@&reloaddir=true", self.repoId, [path escapedUrl]];

    [connection sendPost:requestUrl form:@"operation=mkdir"
                 success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         Debug("requestUrl:%@ resp=%ld\n", requestUrl, (long)response.statusCode);
         [self handleResponse:response json:JSON];
         if (success) success(self);
     }
                 failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         Warning("requestUrl:%@ resp=%ld\n", requestUrl, (long)response.statusCode);
         [self.delegate download:self failed:error];
         if (failure) failure(self, error);
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
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         Warning("resp=%ld\n", (long)response.statusCode);
         [self.delegate download:self failed:error];
     }];
}

- (void)delEntries:(NSArray *)entries success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure
{
    int i = 0;
    NSAssert(entries.count > 0, @"There must be at least one entry");
    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/fileops/delete/?p=%@&reloaddir=true", self.repoId, [self.path escapedUrl]];

    NSMutableString *form = [[NSMutableString alloc] init];
    [form appendFormat:@"file_names=%@", [[entries objectAtIndex:0] escapedPostForm]];

    for (i = 1; i < entries.count; ++i) {
        [form appendFormat:@":%@", [[entries objectAtIndex:i] escapedPostForm]];
    }

    [connection sendPost:requestUrl form:form
                 success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         Debug("resp=%ld\n", (long)response.statusCode);
         [self handleResponse:response json:JSON];
         if (success) success(self);
     }
                 failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         Warning("resp=%ld\n", (long)response.statusCode);
         [self.delegate download:self failed:error];
         if (failure) failure(self, error);
     }];
}
- (void)delEntries:(NSArray *)entries
{
    [self delEntries:entries success:nil failure:nil];
}

- (NSArray *)allItems
{
    if (_allItems)
        return _allItems;

    NSMutableArray *arr = [[NSMutableArray alloc] init];
    [arr addObjectsFromArray:_items];
     @synchronized(_uploadLock) {
         [arr addObjectsFromArray:self.uploadItems];
     }
    [self sortItems:arr];
    _allItems = arr;
    return _allItems;
}

- (BOOL)nameExist:(NSString *)name
{
    for (SeafBase *entry in _items) {
        if ([[name precomposedStringWithCanonicalMapping] isEqualToString:[entry.name precomposedStringWithCanonicalMapping]])
            return true;
    }
    return false;
}

- (void)loadContent:(BOOL)force;
{
    if (force) {
        _uploadItems = nil;
    }
    _allItems = nil;
    [super loadContent:force];
    Debug("repoId:%@, %@, path:%@, loading ... cached:%d %@, editable:%d, state:%d\n", self.repoId, self.name, self.path, self.hasCache, self.ooid, self.editable, self.state);
}

- (NSMutableArray *)uploadItems
{
    if (self.path && !_uploadItems)
        _uploadItems = [NSMutableArray arrayWithArray:[[SeafDataTaskManager sharedObject] getUploadTasksInDir:self connection:self->connection]];
    
    return _uploadItems;
}

- (NSArray *)uploadFiles
{
    @synchronized(_uploadLock) {
        return [NSArray arrayWithArray:self.uploadItems];
    }
}

- (void)addUploadFile:(SeafUploadFile *)file
{
    @synchronized(_uploadLock) {
        if ([self.uploadItems containsObject:file]) return;
    }
    file.udir = self;
    @synchronized(_uploadLock) {
        [self.uploadItems addObject:file];
    }
    _allItems = nil;
    if (!file.uploadFileAutoSync) [self.delegate download:self complete:true];
}

- (void)removeUploadItem:(SeafUploadFile *)ufile
{
    @synchronized(_uploadLock) {
        [self.uploadItems removeObject:ufile];
    }
    _allItems = nil;
}

- (void)renameEntry:(NSString *)oldName newName:(NSString *)newName success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure
{
    NSString *filePath = [self.path stringByAppendingPathComponent:oldName];
    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@&reloaddir=true", self.repoId, [filePath escapedUrl]];
    NSString *form = [NSString stringWithFormat:@"operation=rename&newname=%@", [newName escapedUrl]];
    [connection sendPost:requestUrl form:form
                 success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         Debug("resp=%ld\n", (long)response.statusCode);
         [self handleResponse:response json:JSON];
         if (success)  success(self);
     }
                 failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         Warning("resp=%ld\n", (long)response.statusCode);
         [self.delegate download:self failed:error];
         if (failure) failure(self, error);
     }];
}
- (void)renameEntry:(NSString *)oldName newName:(NSString *)newName
{
    [self renameEntry:oldName newName:newName success:nil failure:nil];
}

- (void)copyEntries:(NSArray *)entries dstDir:(SeafDir *)dir success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure
{
    int i = 0;
    NSAssert(entries.count > 0, @"There must be at least one entry");
    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/fileops/copy/?p=%@&reloaddir=true", self.repoId, [self.path escapedUrl]];

    NSMutableString *form = [[NSMutableString alloc] init];
    [form appendFormat:@"dst_repo=%@&dst_dir=%@&file_names=%@", dir.repoId, [dir.path escapedUrl], [[entries objectAtIndex:0] escapedPostForm]];

    for (i = 1; i < entries.count; ++i) {
        [form appendFormat:@":%@", [[entries objectAtIndex:i] escapedPostForm]];
    }

    [connection sendPost:requestUrl form:form
                 success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         Debug("resp=%ld\n", (long)response.statusCode);
         [self handleResponse:response json:JSON];
         if (success) success(self);
     }
                 failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         Warning("resp=%ld\n", (long)response.statusCode);
         [self.delegate download:self failed:error];
         if (failure) failure(self, error);
     }];
}
- (void)copyEntries:(NSArray *)entries dstDir:(SeafDir *)dstDir
{
    [self copyEntries:entries dstDir:dstDir success:nil failure:nil];
}

- (void)moveEntries:(NSArray *)entries dstDir:(SeafDir *)dir success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir, NSError *error))failure
{
    int i = 0;
    NSAssert(entries.count > 0, @"There must be at least one entry");
    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/fileops/move/?p=%@&reloaddir=true", self.repoId, [self.path escapedUrl]];

    NSMutableString *form = [[NSMutableString alloc] init];
    [form appendFormat:@"dst_repo=%@&dst_dir=%@&file_names=%@", dir.repoId, [dir.path escapedUrl], [[entries objectAtIndex:0] escapedPostForm]];

    for (i = 1; i < entries.count; ++i) {
        [form appendFormat:@":%@", [[entries objectAtIndex:i] escapedPostForm]];
    }

    [connection sendPost:requestUrl form:form
                 success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         Debug("resp=%ld\n", (long)response.statusCode);
         [self handleResponse:response json:JSON];
         if (success) success(self);
     }
                 failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error) {
         Warning("resp=%ld\n", (long)response.statusCode);
         [self.delegate download:self failed:error];
         if (failure) failure(self, error);
     }];
}

- (void)moveEntries:(NSArray *)entries dstDir:(SeafDir *)dstDir
{
    [self moveEntries:entries dstDir:dstDir success:nil failure:nil];
}

- (NSArray *)subDirs
{
    NSMutableArray *arr = [[NSMutableArray alloc] init];
    for (SeafBase *entry in self.items) {
        if ([entry isKindOfClass:[SeafDir class]])
            [arr addObject:entry];
    }
    return arr;
}

@end
