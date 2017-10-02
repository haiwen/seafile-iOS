//
//  SeafTaskQueue.h
//  Pods
//
//  Created by three on 2017/10/2.
//
//

#import <Foundation/Foundation.h>
#import "SeafFile.h"

@interface SeafTaskQueue : NSObject

@property (nonatomic, strong) NSMutableArray *tasks;
@property (nonatomic, strong) NSMutableArray *ongoingTasks;
@property (nonatomic, assign) NSInteger concurrency;

- (NSArray *)allTasks;
- (void)addTask:(id)task;
- (void)finishTask:(id<SeafDownloadDelegate>)task result:(BOOL)result;
- (void)finishUploadTask:(SeafUploadFile*)task result:(BOOL)result;
- (NSInteger)downloadingNum;
- (void)clear;

@end
