//
//  SeafThumb.h
//  seafilePro
//
//  Created by Wang Wei on 9/9/16.
//  Copyright © 2016 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SeafConnection.h"
#import "SeafPreView.h"

@interface SeafThumb : NSObject<SeafDownloadDelegate>
@property (retain, readonly) id<SeafPreView> file;

- (id)initWithSeafPreviewIem:(id<SeafPreView>)file;

@end
