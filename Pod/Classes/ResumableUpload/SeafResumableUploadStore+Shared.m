//
//  SeafResumableUploadStore+Shared.m
//  Seafile
//
//  Kept apart from the store itself so the store can be compiled and tested
//  without the rest of the SDK.
//

#import "SeafResumableUploadStore.h"
#import "SeafStorage.h"
#import "Utils.h"
#import "Debug.h"

@implementation SeafResumableUploadStore (Shared)

+ (instancetype)sharedStore
{
    static SeafResumableUploadStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *root = SeafStorage.sharedObject.rootPath;
        if (root.length == 0) {
            Warning("No storage root, resumable uploads disabled");
            return;
        }
        store = [[SeafResumableUploadStore alloc] initWithPath:[root stringByAppendingPathComponent:@"resumable-uploads.sqlite"]];
        // Lets a relaunched app take its own interrupted uploads over at once.
        if ([Utils isMainApp]) store.mainAppLaunchId = [NSUUID UUID].UUIDString;
    });
    return store;
}

@end
