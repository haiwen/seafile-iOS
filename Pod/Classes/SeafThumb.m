//
//  SeafThumb.m
//  seafilePro
//
//  Created by Wang Wei on 9/9/16.
//  Copyright © 2016 Seafile. All rights reserved.
//

#import "SeafThumb.h"
#import "SeafFile.h"
#import "Debug.h"

@implementation SeafThumb
@synthesize lastFailureTimestamp = _lastFailureTimestamp;
@synthesize retryable = _retryable;

- (id)initWithSeafFile:(SeafFile *)file
{
    if ((self = [super init])) {
        _file = file;
        self.retryable = false;
    }
    return self;
}

- (NSString *)accountIdentifier
{
    return self.file->connection.accountIdentifier;
}

- (void)run:(TaskCompleteBlock _Nullable)block
{
    if (!block) {
        block = ^(id<SeafTask> task, BOOL result) {};
    }
    [self download:block];
}

- (void)download:(TaskCompleteBlock _Nonnull)completeBlock
{
    [self.file downloadThumb:^(BOOL result){
        completeBlock(self, result);
    }];
}

- (BOOL)runable
{
    return true;
}

- (NSString *)name
{
    return [_file.name stringByAppendingString:@"(-thumb)"];
}

- (void)cancel
{
    [self.file cancelThumb];
}


@end
