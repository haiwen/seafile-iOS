//
//  SeafUploadDirVontrollerViewController.h
//  seafile
//
//  Created by Wang Wei on 10/20/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "SeafDir.h"

typedef NS_ENUM(NSUInteger, OperationState) {
    OPERATION_STATE_COPY,
    OPERATION_STATE_MOVE,
    OPERATION_STATE_OTHER,
};

typedef void (^SeafDirChoose)(UIViewController *c, SeafDir *dir);
typedef void (^SeafDirCancelChoose)(UIViewController *c);


@protocol SeafDirDelegate <NSObject>
- (void)chooseDir:(UIViewController *)c dir:(SeafDir *)dir;
- (void)cancelChoose:(UIViewController *)c;

@end

@interface SeafDirViewController : UITableViewController

@property (nonatomic, assign) OperationState operationState;
// When enabled, adjust cell content for destination picker (e.g., show detail for normal dirs)
@property (nonatomic, assign) BOOL useDestinationStyle;
// When YES, show the "return to parent" header even at the root controller
@property (nonatomic, assign) BOOL showReturnHeaderOnRoot;

- (id)initWithSeafDir:(SeafDir *)dir delegate:(id<SeafDirDelegate>)delegate chooseRepo:(BOOL)chooseRepo;
- (id)initWithSeafDir:(SeafDir *)dir dirChosen:(SeafDirChoose)choose cancel:(SeafDirCancelChoose)cancel chooseRepo:(BOOL)chooseRepo;

@end
