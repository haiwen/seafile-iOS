//
//  SeafTextEditorViewController.h
//  seafile
//
//  Created by Wang Wei on 4/9/13.
//  Copyright (c) 2013 Seafile Ltd.  All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SeafDetailViewController.h"
#import "SeafFile.h"

@interface SeafTextEditorViewController : UIViewController<UITextViewDelegate>

@property (strong) SeafDetailViewController *detailViewController;

- (id)initWithFile:(id<SeafPreView>)file;

@end
