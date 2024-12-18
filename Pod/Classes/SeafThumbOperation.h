//
//  SeafThumbOperation.h
//  Pods
//
//  Created by henry on 2024/11/11.
//

#import <Foundation/Foundation.h>
#import "SeafFile.h"

NS_ASSUME_NONNULL_BEGIN

@interface SeafThumbOperation : NSOperation

@property (nonatomic, strong) SeafFile *file;

- (instancetype)initWithSeafFile:(SeafFile *)file;

@end

NS_ASSUME_NONNULL_END


