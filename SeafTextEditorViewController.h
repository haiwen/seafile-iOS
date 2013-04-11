//
//  SeafTextEditorViewController.h
//  seafile
//
//  Created by Wang Wei on 4/9/13.
//  Copyright (c) 2013 tsinghua. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "SeafFile.h"

@interface SeafTextEditorViewController : UIViewController<UIWebViewDelegate>

- (void) setFile:(id<QLPreviewItem, PreViewDelegate>) file;

@end
