//
//  SeafPhoto.h
//  seafilePro
//
//  Created by Wang Wei on 10/17/15.
//  Copyright © 2015 Seafile. All rights reserved.
//
#import "MWPhoto.h"

#import "SeafPreView.h"
@interface SeafPhoto : NSObject<MWPhoto>
@property (retain, readonly) id<SeafPreView> file;


- (id)initWithSeafPreviewIem:(id<SeafPreView>)file;

- (void)setProgress: (float)progress;
- (void)complete:(BOOL)updated error:(NSError *)error;
@end
