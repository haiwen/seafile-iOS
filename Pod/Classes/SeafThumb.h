//
//  SeafThumb.h
//  seafilePro
//
//  Created by Wang Wei on 9/9/16.
//  Copyright © 2016 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SeafFile.h"
#import "FileMimeType.h"
/**
 * @class SeafThumb
 * @discussion The SeafThumb class is used to handle thumbnail retrieval tasks for files within the Seafile service.
 */
@interface SeafThumb : NSObject<SeafTask>
@property (retain, readonly) SeafFile *file;/// The SeafFile associated with this thumbnail task.

/**
 * Initializes a new SeafThumb instance for a given SeafFile.
 * @param file The SeafFile object for which the thumbnail needs to be fetched.
 * @return An initialized SeafThumb object or nil if an object could not be created for some reason.
 */
- (id)initWithSeafFile:(SeafFile *)file;
- (void)cancel;

@end
