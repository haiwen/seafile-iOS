//
//  NSObject+SeafDbCacheProvider.m
//  Pods
//
//  Created by Wei W on 4/8/17.
//
//

#import <CoreData/CoreData.h>
#import "SeafDbCacheProvider.h"
#import "SeafStorage.h"
#import "SeafData.h"
#import "Debug.h"


@interface SeafDbCacheProvider()

@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (strong, nonatomic) NSFetchedResultsController *fetchedResultsController;

@end


@implementation SeafDbCacheProvider
@synthesize managedObjectContext = __managedObjectContext;
@synthesize managedObjectModel = __managedObjectModel;
@synthesize persistentStoreCoordinator = __persistentStoreCoordinator;

#pragma mark - Core Data stack
- (NSManagedObjectContext *)managedObjectContext
{
    if (__managedObjectContext != nil) {
        return __managedObjectContext;
    }

    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        __managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [__managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
    return __managedObjectContext;
}

// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (__managedObjectModel != nil) {
        return __managedObjectModel;
    }
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"seafile" withExtension:@"momd"];
    __managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return __managedObjectModel;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (__persistentStoreCoordinator != nil) {
        return __persistentStoreCoordinator;
    }
    NSURL *storeURL = [[SeafStorage.sharedObject rootURL] URLByAppendingPathComponent:@"seafile_pro.sqlite"];
    Debug("storeURL: %@", storeURL);
    if (!storeURL) {
        Warning("nil store URL");
        return nil;
    }
    NSMutableDictionary *options = [[NSMutableDictionary alloc] init];
    [options setObject:[NSNumber numberWithBool:YES] forKey:NSMigratePersistentStoresAutomaticallyOption];
    [options setObject:[NSNumber numberWithBool:YES] forKey:NSInferMappingModelAutomaticallyOption];


    NSError *error = nil;
    __persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    if (![__persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error]) {
        /*
         Replace this implementation with code to handle the error appropriately.

         abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

         Typical reasons for an error here include:
         * The persistent store is not accessible;
         * The schema for the persistent store is incompatible with current managed object model.
         Check the error message to determine what the actual problem was.


         If the persistent store is not accessible, there is typically something wrong with the file path. Often, a file URL is pointing into the application's resources directory instead of a writeable directory.

         If you encounter schema incompatibility errors during development, you can reduce their frequency by:
         * Simply deleting the existing store:
         [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil]

         * Performing automatic lightweight migration by passing the following dictionary as the options parameter:
         [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption, [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];

         Lightweight migration will only work for a limited set of schema changes; consult "Core Data Model Versioning and Data Migration Programming Guide" for details.

         */
        [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil];

        if (![__persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
            Warning("Unresolved error %@, %@", error, [error userInfo]);
        }
    }

    return __persistentStoreCoordinator;
}

- (void)saveContext
{
    __block NSError *error = nil;
    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    if (managedObjectContext != nil) {
        if ([managedObjectContext hasChanges]) {
            [managedObjectContext performBlockAndWait:^{
                BOOL ret = [managedObjectContext save:&error];
                if (!ret) {
                    Warning("Unresolved error %@", error);
                }
            }];
        }
    }
}

- (void)migrateUploadedPhotos:(NSString *)url username:(NSString *)username account:(NSString *)account
{
    NSManagedObjectContext *context = self.managedObjectContext;

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"UploadedPhotos" inManagedObjectContext:context];
    [fetchRequest setEntity:entity];

    NSError *error = nil;
    NSArray *items = [context executeFetchRequest:fetchRequest error:&error];
    if (error) {
        Warning("Failed to load history upload photos: %@.", error);
        return;
    }

    Info("Account: %@, migrate db table UploadedPhotos to UploadedPhotoV2 : %ld", account, (long)items.count);
    for (UploadedPhotos *obj in items) {
        UploadedPhotoV2 *objV2 = [NSEntityDescription insertNewObjectForEntityForName:ENTITY_UPLOAD_PHOTO inManagedObjectContext:context];
        objV2.account = account;
        objV2.key = obj.url;
        objV2.value = @"";
    }
    if (![context save:&error]) {
        Warning("Failed to migrate from UploadedPhotos to UploadedPhotoV2.");
    } else {
        [self deleteAllObjectsForEntity:@"UploadedPhotos"];
    }
}

- (SeafCacheObjV2 *)getCacheObj:(NSString *)key entityName:(NSString *)entity inAccount:(NSString *)account
{
    NSManagedObjectContext *context = self.managedObjectContext;
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    [fetchRequest setEntity:[NSEntityDescription entityForName:entity inManagedObjectContext:context]];
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"key" ascending:YES selector:nil];
    NSArray *descriptor = [NSArray arrayWithObject:sortDescriptor];
    [fetchRequest setSortDescriptors:descriptor];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"account==%@ AND key==%@", account, key]];
    NSFetchedResultsController *controller = [[NSFetchedResultsController alloc]
                                              initWithFetchRequest:fetchRequest
                                              managedObjectContext:context
                                              sectionNameKeyPath:nil
                                              cacheName:nil];
    _fetchedResultsController = controller;
    __block NSError *error = nil;
    __block BOOL ret = NO;
    [context performBlockAndWait:^{
        ret = [_fetchedResultsController performFetch:&error];
        if (!ret) {
            Warning("Fetch cache error %@", [error localizedDescription]);
        }
    }];
    if (!ret) {
        return nil;
    }
    
    __block NSArray *results;
    [context performBlockAndWait:^{
        results = [_fetchedResultsController fetchedObjects];
    }];
    _fetchedResultsController = nil;
    if (results == nil || [results count] == 0) {
        return nil;
    }
    return [results objectAtIndex:0];
}

- (NSString *)objectForKey:(NSString *)key entityName:(NSString *)entity inAccount:(NSString *)account
{
    SeafCacheObjV2 *obj = [self getCacheObj:key entityName:entity inAccount:account];
    if (obj) {
        @try {
            return obj.value;
        } @catch (NSException *exception) {
            Warning("Failed to get value!");
            return nil;
        }
    }
    return nil;
}

- (BOOL)setValue:(NSString *)value forKey:(NSString *)key entityName:(NSString *)entity inAccount:(NSString *)account
{
    NSManagedObjectContext *context = self.managedObjectContext;
    SeafCacheObjV2 *obj = [self getCacheObj:key entityName:entity inAccount:account];
    if (!obj) {
        obj = (SeafCacheObjV2 *)[NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:context];
        obj.account = account;
        obj.key = key;
        obj.value = value;
    } else {
        obj.value = value;
    }

    [self saveContext];
    return YES;
}

- (void)removeKey:(NSString *)key entityName:(NSString *)entity inAccount:(NSString *)account
{
    NSManagedObjectContext *context = self.managedObjectContext;
    __block SeafCacheObjV2 *obj = [self getCacheObj:key entityName:entity inAccount:account];
    if (obj != nil) {
        [context performBlockAndWait:^{
            [context deleteObject:obj];
        }];
        [self saveContext];
    }
}

- (long)totalCachedNumForEntity:(NSString *)entity inAccount:(NSString *)account
{
    NSManagedObjectContext *context = self.managedObjectContext;
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    [request setEntity:[NSEntityDescription entityForName:entity inManagedObjectContext:context]];
    [request setIncludesSubentities:NO];
    [request setPredicate:[NSPredicate predicateWithFormat:@"account==%@", account]];

    __block NSUInteger count = 0;
    [context performBlockAndWait:^{
        NSError *err;
        count = [context countForFetchRequest:request error:&err];
        if (err) {
            Warning("Fetch count error %@", [err localizedDescription]);
        }
    }];
    if(count == NSNotFound) {
        Warning("Failed to fet synced count");
        return 0;
    }

    return count;
}

- (void)clearCache:(NSString *)entity inAccount:(NSString *)account
{
    NSManagedObjectContext *context = self.managedObjectContext;
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    [request setEntity:[NSEntityDescription entityForName:entity inManagedObjectContext:context]];
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"key" ascending:YES selector:nil];
    NSArray *descriptor = [NSArray arrayWithObject:sortDescriptor];
    [request setSortDescriptors:descriptor];
    [request setPredicate:[NSPredicate predicateWithFormat:@"account==%@", account]];

    NSFetchedResultsController *controller = [[NSFetchedResultsController alloc]
                                              initWithFetchRequest:request
                                              managedObjectContext:context
                                              sectionNameKeyPath:nil
                                              cacheName:nil];
    _fetchedResultsController = controller;
    __block BOOL ret = NO;
    
    [context performBlockAndWait:^{
        NSError *error = nil;
        ret = [_fetchedResultsController performFetch:&error];
        if (error) {
            Warning("Fetch cache error %@", [error localizedDescription]);
        }
    }];
    if (!ret) {
        return;
    }
    
    for (id obj in _fetchedResultsController.fetchedObjects) {
        [context performBlockAndWait:^{
            [context deleteObject:obj];
        }];
    }
    _fetchedResultsController = nil;
    [self saveContext];
}

- (void)deleteAllObjectsForEntity:(NSString *)entityDescription
{
    NSManagedObjectContext *context = self.managedObjectContext;

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:entityDescription inManagedObjectContext:context];
    [fetchRequest setEntity:entity];

    __block NSError *error = nil;
    __block NSArray *items;;
    [context performBlockAndWait:^{
        items = [context executeFetchRequest:fetchRequest error:&error];
        if (error) {
            Debug(@"Fetch error:%@",[error localizedDescription]);
        }
    }];

    for (NSManagedObject *managedObject in items) {
        [context performBlockAndWait:^{
            [context deleteObject:managedObject];
        }];
    }
    error = nil;
    [context performBlockAndWait:^{
        BOOL savedOK = [context save:&error];
        if (!savedOK) {
            Debug(@"Error deleting %@ - error:%@",entityDescription,error);
        }
    }];
}

- (void)clearAllCacheInAccount:(NSString *)account
{
    // Uploaded phots should not be cleared
    [self clearCache:ENTITY_FILE inAccount:account];
    [self clearCache:ENTITY_DIRECTORY inAccount:account];
    [self clearCache:ENTITY_OBJECT inAccount:account];
    [self deleteAllObjectsForEntity:@"Directory"];
    [self deleteAllObjectsForEntity:@"DownloadedFile"];
    [self deleteAllObjectsForEntity:@"SeafCacheObj"];
    [self deleteAllObjectsForEntity:@"UploadedPhotos"];
}

@end
