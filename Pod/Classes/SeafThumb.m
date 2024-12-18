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
//@synthesize lastFinishTimestamp = _lastFinishTimestamp;
//@synthesize retryable = _retryable;
//@synthesize retryCount = _retryCount;

- (id)initWithSeafFile:(SeafFile *)file
{
    if ((self = [super init])) {
        _file = file;
//        self.retryable = false;
    }
    return self;
}

- (NSString *)accountIdentifier
{
    return self.file->connection.accountIdentifier;
}

//- (void)run:(TaskCompleteBlock _Nullable)completeBlock
//{
//    if (!completeBlock) {
//        completeBlock = ^(id<SeafTask> task, BOOL result) {};
//    }
//    if (self.file.thumbFailedCount >= DEFAULT_RETRYCOUNT) {
//        return completeBlock(self, YES);
//    }
//
//    [self download:completeBlock];
//}

//- (void)setTaskProgressBlock:(TaskProgressBlock _Nullable)taskProgressBlock
//{
//
//}

//- (void)download:(TaskCompleteBlock _Nonnull)completeBlock
//{
//    [self.file downloadThumb:^(BOOL result){
//        completeBlock(self, result);
//    }];
//}

//- (BOOL)runable
//{
//    return true;
//}

- (NSString *)name
{
    return [_file.name stringByAppendingString:@"(-thumb)"];
}

//- (void)cancel
//{
//    [self.file cancelThumb];
//}

@end
