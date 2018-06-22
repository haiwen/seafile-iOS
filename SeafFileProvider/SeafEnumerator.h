//
//  SeafFileProviderEnumerator.h
//  SeafFileProvider
//
//  Created by Wei W on 11/5/17.
//  Copyright © 2017 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <FileProvider/FileProvider.h>
#import "SeafItem.h"

@interface SeafEnumerator : NSObject<NSFileProviderEnumerator>

- (instancetype)initWithItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier containerItemIdentifier:(NSFileProviderItemIdentifier)containerItemIdentifier currentAnchor:(NSInteger)currentAnchor;

- (instancetype)initWithSeafItem:(SeafItem *)item;

@end
