//
//  SeafThumbOperation.h
//  Pods
//
//  Created by henry on 2024/11/11.
//

#import <Foundation/Foundation.h>
#import "SeafFile.h"

@class SeafThumb;

NS_ASSUME_NONNULL_BEGIN

@interface SeafThumbOperation : NSOperation

@property (nonatomic, strong) SeafFile *file;

/// The queue task this operation was created for, reported back on completion so
/// the file only clears its slot when this task is still the current one.
@property (nonatomic, strong, nullable) SeafThumb *thumb;

- (instancetype)initWithSeafFile:(SeafFile *)file;

@end

NS_ASSUME_NONNULL_END


