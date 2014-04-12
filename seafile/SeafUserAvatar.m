//
//  SeafAvatar.m
//  seafilePro
//
//  Created by Wang Wei on 4/11/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import "SeafUserAvatar.h"
#import "SeafAppDelegate.h"

#import "Utils.h"
#import "Debug.h"

@interface SeafUserAvatar()
@property SeafConnection *connection;
@property NSString *username;
@end

@implementation SeafUserAvatar


- (id)initWithConnection:(SeafConnection *)aConnection username:(NSString *)username
{
    self = [super init];
    self.connection = aConnection;
    self.username = username;
    return self;
}

- (void)download
{
    [SeafAppDelegate incDownloadnum];
    [self.connection sendRequest:[NSString stringWithFormat:API_URL"/avatars/user/%@/resized/%d", self.username, 72] repo:nil success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON, NSData *data) {
         NSString *url = JSON;
         url = [url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
         NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
         AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:downloadRequest];
         operation.securityPolicy = [SeafConnection defaultPolicy];
         NSString *path = [SeafUserAvatar pathForUserAvatar:self.connection username:self.username];
         NSString *tmppath = [[SeafUserAvatar pathForUserAvatar:self.connection username:self.username] stringByAppendingString:@"-tmp"];
         operation.outputStream = [NSOutputStream outputStreamToFileAtPath:tmppath append:NO];
         [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
             Debug("Successfully downloaded file");
             [[NSFileManager defaultManager] moveItemAtPath:tmppath toPath:path error:nil];
             [SeafAppDelegate finishDownload:self result:YES];
         } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
             Debug("error=%@",[error localizedDescription]);
             [SeafAppDelegate finishDownload:self result:NO];
         }];
         [operation start];
     }
                    failure:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
         Warning("Failed to download avatar %@ from %@", self.username, self.connection.address);
     }];
}

+ (NSString *)pathForUserAvatar:(SeafConnection *)conn username:(NSString *)username
{
    NSURL *url = [NSURL URLWithString:conn.address];
    NSString *filename = [NSString stringWithFormat:@"%@-%@.jpg", url.host, username];
    NSString *path = [[[Utils applicationDocumentsDirectory]stringByAppendingPathComponent:@"avatars"] stringByAppendingPathComponent:filename];
    Debug("path=%@", path);
    return path;
}

@end
