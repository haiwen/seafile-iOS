//
//  SeafThumb.h
//  seafilePro
//
//  Created by Wang Wei on 11/21/15.
//  Copyright © 2015 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MWPhoto.h>

#import "SeafPreView.h"

@interface SeafThumb : NSObject<MWPhoto>
@property (retain, readonly) id<SeafPreView> file;


- (id)initWithSeafPreviewIem:(id<SeafPreView>)file;
@end
