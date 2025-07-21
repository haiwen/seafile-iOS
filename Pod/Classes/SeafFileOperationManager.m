//
//  SeafFileOperationManager.m
//  Seafile
//
//  Created by Henry on 2025/1/20.
//

#import "SeafFileOperationManager.h"
#import "Debug.h"
#import "Utils.h"
#import "SeafDir.h"
#import "SeafConnection.h"   // Required to get connection
#import "ExtentedString.h"   // For escapedUrl, escapedPostForm
#import "SeafBase.h"         // Required for repoId property
#import "SeafRepos.h"

@implementation SeafFileOperationManager

+ (instancetype)sharedManager {
    static SeafFileOperationManager *mgr = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mgr = [[SeafFileOperationManager alloc] init];
    });
    return mgr;
}

#pragma mark - Create File
- (void)createFile:(NSString *)fileName
             inDir:(SeafDir *)directory
        completion:(SeafOperationCompletion)completion
{
    if (!fileName || fileName.length == 0) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"SeafFileOperation"
                                               code:-1
                                           userInfo:@{NSLocalizedDescriptionKey:@"File name must not be empty"}];
            completion(NO, err);
        }
        return;
    }

    // Directly construct requestUrl
    NSString *fullPath = [directory.path stringByAppendingPathComponent:fileName];
    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@&reloaddir=true",
                            directory.repoId, [fullPath escapedUrl]];

    [directory.connection sendPost:requestUrl
                              form:@"operation=create"
                           success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
    {
        Debug("Create file success, statusCode=%ld", (long)response.statusCode);
        // Parse JSON and refresh directory data:
        [directory handleResponse:response json:JSON]; // optional, if you want dir->items updated
        if (completion) completion(YES, nil);
    }
                           failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error)
    {
        Warning("Create file failed, statusCode=%ld", (long)response.statusCode);
        if (completion) completion(NO, error);
    }];
}


#pragma mark - Create Folder (mkdir)
- (void)mkdir:(NSString *)folderName
        inDir:(SeafDir *)directory
    completion:(SeafOperationCompletion)completion
{
    if (!folderName || folderName.length == 0) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"SeafFileOperation"
                                               code:-2
                                           userInfo:@{NSLocalizedDescriptionKey:@"Folder name must not be empty"}];
            completion(NO, err);
        }
        return;
    }
    
    NSString *fullPath = [directory.path stringByAppendingPathComponent:folderName];
    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/dir/?p=%@&reloaddir=true",
                            directory.repoId, [fullPath escapedUrl]];

    [directory.connection sendPost:requestUrl
                              form:@"operation=mkdir"
                           success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
    {
        Debug("Mkdir success, code=%ld", (long)response.statusCode);
        if ([JSON isKindOfClass:[NSDictionary class]]) {
            // Server returned dir metadata dictionary; we can process directly.
            [directory handleResponse:response json:JSON];
        } else {
            // Response format unexpected (e.g. array or simple string). Fall back to reloading directory content.
            [directory loadContent:YES];
        }
        if (completion) completion(YES, nil);
    }
                           failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error)
    {
        Warning("Mkdir failed, code=%ld", (long)response.statusCode);
        if (completion) completion(NO, error);
    }];
}


#pragma mark - Delete
- (void)deleteEntries:(NSArray<NSString *> *)entries
               inDir:(SeafDir *)directory
          completion:(SeafOperationCompletion)completion
{
    if (!entries || entries.count == 0) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"SeafFileOperation"
                                               code:-3
                                           userInfo:@{NSLocalizedDescriptionKey:@"No entries to delete"}];
            completion(NO, err);
        }
        return;
    }

    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/fileops/delete/?p=%@&reloaddir=true",
                            directory.repoId, [directory.path escapedUrl]];

    NSMutableString *form = [NSMutableString new];
    [form appendFormat:@"file_names=%@", [[entries firstObject] escapedPostForm]];
    for (NSInteger i = 1; i < entries.count; ++i) {
        [form appendFormat:@":%@", [entries[i] escapedPostForm]];
    }

    [directory.connection sendPost:requestUrl
                              form:form
                           success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
    {
        Debug("Delete success, code=%ld", (long)response.statusCode);
        [directory handleResponse:response json:JSON]; // optional
        if (completion) completion(YES, nil);
    }
                           failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error)
    {
        Warning("Delete failed, code=%ld", (long)response.statusCode);
        if (completion) completion(NO, error);
    }];
}


#pragma mark - Rename
- (void)renameEntry:(NSString *)oldName
            newName:(NSString *)newName
              inDir:(SeafDir *)directory
         completion:(void(^)(BOOL success, SeafBase *renamedFile, NSError *error))completion
{
    if (!oldName || oldName.length == 0 || !newName || newName.length == 0) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"SeafFileOperation"
                                             code:-4
                                         userInfo:@{NSLocalizedDescriptionKey:@"Invalid rename parameters"}];
            completion(NO, nil, err);
        }
        return;
    }

    NSString *oldPath = [directory.path stringByAppendingPathComponent:oldName];
    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/file/?p=%@&reloaddir=true",
                            directory.repoId, [oldPath escapedUrl]];
    NSString *form = [NSString stringWithFormat:@"operation=rename&newname=%@", [newName escapedUrl]];

    [directory.connection sendPost:requestUrl
                            form:form
                         success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
    {
        Debug("Rename success, code=%ld", (long)response.statusCode);
        [directory handleResponse:response json:JSON];
        
        // Find the renamed file in directory items
        SeafBase *renamedFile = nil;
        for (SeafBase *obj in directory.items) {
            if ([obj.name.precomposedStringWithCompatibilityMapping isEqualToString:newName.precomposedStringWithCompatibilityMapping]) {
                renamedFile = obj;
                [renamedFile loadCache];
                break;
            }
        }
        
        if (completion) {
            if (renamedFile) {
                completion(YES, renamedFile, nil);
            } else {
                NSError *err = [NSError errorWithDomain:@"SeafFileOperation"
                                                 code:-5
                                             userInfo:@{NSLocalizedDescriptionKey:@"Renamed file not found"}];
                completion(NO, nil, err);
            }
        }
    }
                         failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error)
    {
        Warning("Rename failed, code=%ld", (long)response.statusCode);
        if (completion) completion(NO, nil, error);
    }];
}

- (void)renameEntry:(NSString *)oldName
            newName:(NSString *)newName
             inRepo:(SeafRepo *)repo
         completion:(void(^)(BOOL success, SeafBase *renamedFile, NSError *error))completion
{
    if (!oldName || oldName.length == 0 || !newName || newName.length == 0) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"SeafFileOperation"
                                             code:-4
                                         userInfo:@{NSLocalizedDescriptionKey:@"Invalid rename parameters"}];
            completion(NO, nil, err);
        }
        return;
    }

    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/?op=rename",
                            repo.repoId];
    NSString *form = [NSString stringWithFormat:@"repo_name=%@", [newName escapedUrl]];

    [repo.connection sendPost:requestUrl
                            form:form
                         success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
    {
        Debug("Rename success, code=%ld", (long)response.statusCode);
        [repo handleResponse:response json:JSON];
        
        repo.name = newName;
        
        if (completion) {
            completion(YES, repo, nil);
        }
    }
                         failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error)
    {
        Warning("Rename failed, code=%ld", (long)response.statusCode);
        if (completion) completion(NO, nil, error);
    }];
}


#pragma mark - Copy
- (void)copyEntries:(NSArray<NSString *> *)entries
             fromDir:(SeafDir *)srcDir
               toDir:(SeafDir *)dstDir
          completion:(SeafOperationCompletion)completion
{
    if (!entries || entries.count == 0 || !srcDir || !dstDir) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"SeafFileOperation"
                                               code:-5
                                           userInfo:@{NSLocalizedDescriptionKey:@"Invalid copy parameters"}];
            completion(NO, err);
        }
        return;
    }

    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/fileops/copy/?p=%@&reloaddir=true",
                            srcDir.repoId, [srcDir.path escapedUrl]];
    NSMutableString *form = [NSMutableString new];
    [form appendFormat:@"dst_repo=%@&dst_dir=%@&file_names=%@",
        dstDir.repoId, [dstDir.path escapedUrl], [[entries firstObject] escapedPostForm]];
    for (NSInteger i = 1; i < entries.count; ++i) {
        [form appendFormat:@":%@", [entries[i] escapedPostForm]];
    }

    [srcDir.connection sendPost:requestUrl
                           form:form
                        success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
    {
        Debug("Copy success, code=%ld", (long)response.statusCode);
        // Optionally refresh srcDir or dstDir:
        [srcDir handleResponse:response json:JSON];
        if (completion) completion(YES, nil);
    }
                        failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error)
    {
        Warning("Copy failed, code=%ld", (long)response.statusCode);
        if (completion) completion(NO, error);
        [srcDir.delegate download:srcDir failed:error];
    }];
}


#pragma mark - Move
- (void)moveEntries:(NSArray<NSString *> *)entries
             fromDir:(SeafDir *)srcDir
               toDir:(SeafDir *)dstDir
          completion:(SeafOperationCompletion)completion
{
    if (!entries || entries.count == 0 || !srcDir || !dstDir) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"SeafFileOperation"
                                               code:-6
                                           userInfo:@{NSLocalizedDescriptionKey:@"Invalid move parameters"}];
            completion(NO, err);
        }
        return;
    }

    NSString *requestUrl = [NSString stringWithFormat:API_URL"/repos/%@/fileops/move/?p=%@&reloaddir=true",
                            srcDir.repoId, [srcDir.path escapedUrl]];
    NSMutableString *form = [NSMutableString new];
    [form appendFormat:@"dst_repo=%@&dst_dir=%@&file_names=%@",
        dstDir.repoId, [dstDir.path escapedUrl], [[entries firstObject] escapedPostForm]];
    for (NSInteger i = 1; i < entries.count; ++i) {
        [form appendFormat:@":%@", [entries[i] escapedPostForm]];
    }

    [srcDir.connection sendPost:requestUrl
                           form:form
                        success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
    {
        Debug("Move success, code=%ld", (long)response.statusCode);
        // Optionally refresh
        [srcDir handleResponse:response json:JSON];
        if (completion) completion(YES, nil);
    }
                        failure:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSError *error)
    {
        Warning("Move failed, code=%ld", (long)response.statusCode);
        if (completion) completion(NO, error);
    }];
}

@end
