//
//  SeafDestinationPickerViewController.h
//  seafile
//
//  Created for the redesigned destination picker (copy/move)
//

#import <UIKit/UIKit.h>
#import "SeafDirViewController.h"
#import "SeafConnection.h"

NS_ASSUME_NONNULL_BEGIN

@interface SeafDestinationPickerViewController : UIViewController

@property (nonatomic, weak) id<SeafDirDelegate> delegate;
@property (nonatomic, assign) OperationState operationState;

// Designated initializer
- (instancetype)initWithConnection:(SeafConnection *)connection
                   sourceDirectory:(SeafDir *)sourceDirectory
                           delegate:(id<SeafDirDelegate>)delegate
                    operationState:(OperationState)operationState
                          fileNames:(NSArray<NSString *> *)fileNames;

@end

NS_ASSUME_NONNULL_END


