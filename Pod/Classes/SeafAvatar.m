// SeafAvatar.m

#import "SeafAvatar.h"
#import "SeafConnection.h"
#import "SeafStorage.h"
#import "Utils.h"
#import "Debug.h"

static NSMutableDictionary *avatarAttrs = nil;

@implementation SeafAvatar

- (instancetype)initWithConnection:(SeafConnection *)aConnection email:(NSString *)email
{
    self = [super init];
    if (self) {
        _connection = aConnection;
        _email = email;
        _avatarPath = [self pathForAvatarWithConnection:aConnection email:email];
    }
    return self;
}

- (instancetype)initWithConnection:(SeafConnection *)aConnection from:(NSString *)url toPath:(NSString *)path
{
    self = [super init];
    _connection = aConnection;
    self.avatarUrl = url;
    self.path = path;
    self.retryable = false;
    return self;
}

- (NSString *)pathForAvatarWithConnection:(SeafConnection *)connection email:(NSString *)email
{
    NSString *filename = [NSString stringWithFormat:@"%@-%@.jpg", connection.host, email];
    return [SeafStorage.sharedObject.avatarsDir stringByAppendingPathComponent:filename];
}

- (BOOL)hasAvatar
{
    return [[NSFileManager defaultManager] fileExistsAtPath:self.avatarPath];
}

- (void)downloadComplete:(BOOL)success
{
    if (success) {
        // Update attributes if necessary
    } else {
        // Handle failure if necessary
    }
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

#pragma mark - Avatar Attributes Management

+ (NSMutableDictionary *)avatarAttrs
{
    if (avatarAttrs == nil) {
        NSString *attrsFile = [SeafStorage.sharedObject.avatarsDir stringByAppendingPathComponent:@"avatars.plist"];
        avatarAttrs = [[NSMutableDictionary alloc] initWithContentsOfFile:attrsFile];
        if (!avatarAttrs)
            avatarAttrs = [[NSMutableDictionary alloc] init];
    }
    return avatarAttrs;
}

+ (void)saveAvatarAttrs
{
    NSString *attrsFile = [SeafStorage.sharedObject.avatarsDir stringByAppendingPathComponent:@"avatars.plist"];
    [[SeafAvatar avatarAttrs] writeToFile:attrsFile atomically:YES];
}

+ (void)clearCache
{
    [[NSFileManager defaultManager] removeItemAtPath:[SeafStorage.sharedObject.avatarsDir stringByAppendingPathComponent:@"avatars.plist"] error:nil];
    avatarAttrs = [[NSMutableDictionary alloc] init];
}

- (void)saveAttrs:(NSMutableDictionary *)dict
{
    [[SeafAvatar avatarAttrs] setObject:dict forKey:self.path];
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
    NSString *path = [SeafStorage.sharedObject.avatarsDir stringByAppendingPathComponent:filename];
    return path;
}

@end


