//
//  SeafProviderItem.h
//  SeafProviderFileProvider
//
//  Created by Wei W on 11/5/17.
//  Copyright © 2017 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <FileProvider/FileProvider.h>
#import "SeafItem.h"

@interface SeafProviderItem : NSObject<NSFileProviderItem>

- (instancetype)initWithItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier;
- (instancetype)initWithSeafItem:(SeafItem *)item;
@end
