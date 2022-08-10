//
//  SeafFileProviderUtility.m
//  SeafFileProvider
//
//  Created by three on 2022/8/8.
//  Copyright © 2022 Seafile. All rights reserved.
//

#import "SeafFileProviderUtility.h"
#import "SeafProviderItem.h"

@interface SeafFileProviderUtility()

@property (nonatomic, strong) NSMutableArray *updateItems;

@end

@implementation SeafFileProviderUtility

+ (instancetype)shared {
    static SeafFileProviderUtility *_shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[self alloc] init];
    });
    return _shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.updateItems = [NSMutableArray array];
        self.currentAnchor = 0;
    }
    return self;
}

- (void)saveUpdateItem:(SeafProviderItem *)item {
    if (item && ![self.updateItems containsObject:item]) {
        [self.updateItems addObject:item];
    }
}

- (NSArray *)allUpdateItems {
    return [self.updateItems copy];
}

- (void)removeAllUpdateItems {
    [self.updateItems removeAllObjects];
}

@end
