//
//  SeafFileStateManager.m
//  AFNetworking
//
//  Created by henry on 2025/1/23.
//

#import "SeafFileStateManager.h"
#import "SeafFileStatus.h"
#import "SeafRealmManager.h"

@interface SeafFileStateManager ()
@property (nonatomic, weak) SeafConnection *connection;
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@end

@implementation SeafFileStateManager

- (instancetype)initWithConnection:(SeafConnection *)connection {
    self = [super init];
    if (self) {
        _connection = connection;
        _stateQueue = dispatch_queue_create("com.seafile.statemanager", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)updateFileStatus:(SeafFileModel *)file 
                   state:(SeafFileStatus *)state
             localPath:(NSString *)localPath
{
    dispatch_async(self.stateQueue, ^{
        SeafFileStatus *status = [[SeafFileStatus alloc] init];
        status.uniquePath = file.uniqueKey;
        status.serverOID = file.oid;
        status.localFilePath = localPath;
        status.localMTime = [[NSDate date] timeIntervalSince1970];
        status.accountIdentifier = self.connection.accountIdentifier;
        status.fileName = file.name;
        
        [[SeafRealmManager shared] updateFileStatus:status];
    });
}

@end
