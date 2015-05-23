//
//  SeafAvatar.m
//  seafilePro
//
//  Created by Wang Wei on 4/11/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import "SeafAvatar.h"
#import "SeafGlobal.h"
#import "SeafBase.h"

#import "ExtentedString.h"
#import "Utils.h"
#import "Debug.h"


static NSMutableDictionary *avatarAttrs = nil;


@interface SeafAvatar()
@property SeafConnection *connection;
@property NSString *avatarUrl;
@property NSString *path;
@end

@implementation SeafAvatar

- (id)initWithConnection:(SeafConnection *)aConnection from:(NSString *)url toPath:(NSString *)path
{
    self = [super init];
    self.connection = aConnection;
    self.avatarUrl = url;
    self.path = path;
    return self;
}

+ (NSMutableDictionary *)avatarAttrs
{
    if (avatarAttrs == nil) {
        NSString *attrsFile = [SeafGlobal.sharedObject.avatarsDir stringByAppendingPathComponent:@"avatars.plist"];
        avatarAttrs = [[NSMutableDictionary alloc] initWithContentsOfFile:attrsFile];
        if (!avatarAttrs)
            avatarAttrs = [[NSMutableDictionary alloc] init];
    }
    return avatarAttrs;
}
+ (void)saveAvatarAttrs
{
    NSString *attrsFile = [SeafGlobal.sharedObject.avatarsDir stringByAppendingPathComponent:@"avatars.plist"];
    [[SeafAvatar avatarAttrs] writeToFile:attrsFile atomically:YES];
}

+ (void)clearCache
{
    [Utils clearAllFiles:[SeafGlobal.sharedObject.avatarsDir stringByAppendingPathComponent:@"avatars.plist"]];
    avatarAttrs = [[NSMutableDictionary alloc] init];
}

- (NSMutableDictionary *)attrs
{
    NSMutableDictionary *dict = [[SeafAvatar avatarAttrs] objectForKey:self.path];
    return dict;
}
- (void)saveAttrs:(NSMutableDictionary *)dict
{
    [[SeafAvatar avatarAttrs] setObject:dict forKey:self.path];
}
- (BOOL)modified:(long long)timestamp
{
    NSMutableDictionary *attr = [[SeafAvatar avatarAttrs] objectForKey:self.path];
    if (!attr)
        return YES;
    if ([[attr objectForKey:@"mtime"] integerValue:0] < timestamp)
        return YES;
    return NO;
}
- (void)download
{
    [SeafGlobal.sharedObject incDownloadnum];
    [self.connection sendRequest:self.avatarUrl success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         if (![JSON isKindOfClass:[NSDictionary class]]) {
             [SeafGlobal.sharedObject finishDownload:self result:NO];
             return;
         }
         NSString *url = [JSON objectForKey:@"url"];
         if (!url) {
             [SeafGlobal.sharedObject finishDownload:self result:NO];
             return;
         }
         if([[JSON objectForKey:@"is_default"] integerValue]) {
             if ([[SeafAvatar avatarAttrs] objectForKey:self.path])
                 [[SeafAvatar avatarAttrs] removeObjectForKey:self.path];
             [SeafGlobal.sharedObject finishDownload:self result:YES];
             return;
         }
         if (![self modified:[[JSON objectForKey:@"mtime"] integerValue:0]]) {
             Debug("avatar not modified\n");
             [SeafGlobal.sharedObject finishDownload:self result:YES];
             return;
         }
         url = [[url stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] escapedUrlPath];;
         NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
         NSURLSessionDownloadTask *task = [_connection.sessionMgr downloadTaskWithRequest:downloadRequest progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
             return [NSURL fileURLWithPath:self.path];
         } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
             if (error) {
                 Debug("Failed to download avatar url=%@, error=%@",downloadRequest.URL, [error localizedDescription]);
                 [SeafGlobal.sharedObject finishDownload:self result:NO];
             } else {
                 Debug("Successfully downloaded avatar: %@ from %@", filePath, url);
                 if (![filePath.path isEqualToString:self.path]) {
                     [[NSFileManager defaultManager] removeItemAtPath:self.path error:nil];
                     [[NSFileManager defaultManager] moveItemAtPath:filePath.path toPath:self.path error:nil];
                 }
                 NSMutableDictionary *attr = [[SeafAvatar avatarAttrs] objectForKey:self.path];
                 if (!attr) attr = [[NSMutableDictionary alloc] init];
                 [attr setObject:[JSON objectForKey:@"mtime"] forKey:@"mtime"];
                 [[SeafAvatar avatarAttrs] setObject:attr forKey:self.path];
                 [SeafAvatar saveAvatarAttrs];
                 [SeafGlobal.sharedObject finishDownload:self result:YES];
             }
         }];
         [task resume];
     }
              failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error) {
         Warning("Failed to download avatar from %@", request.URL);
         [SeafGlobal.sharedObject finishDownload:self result:NO];
         [SeafGlobal.sharedObject removeBackgroundDownload:self];
     }];
}
@end


@implementation SeafUserAvatar
- (id)initWithConnection:(SeafConnection *)aConnection username:(NSString *)username
{
    NSString *url = [NSString stringWithFormat:API_URL"/avatars/user/%@/resized/%d/", username, 80];
    NSString *path = [SeafUserAvatar pathForAvatar:aConnection username:username];
    self = [super initWithConnection:aConnection from:url toPath:path];
    return self;
}

+ (NSString *)pathForAvatar:(SeafConnection *)conn username:(NSString *)username
{
    NSString *filename = [NSString stringWithFormat:@"%@-%@.jpg", conn.host, username];
    NSString *path = [SeafGlobal.sharedObject.avatarsDir stringByAppendingPathComponent:filename];
    return path;
}

@end


