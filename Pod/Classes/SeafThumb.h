//
//  SeafThumb.h
//  seafilePro
//
//  Created by Wang Wei on 9/9/16.
//  Copyright © 2016 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SeafFile.h"

@interface SeafThumb : NSObject<SeafTask>
@property (retain, readonly) SeafFile *file;

- (id)initWithSeafFile:(SeafFile *)file;

@end
