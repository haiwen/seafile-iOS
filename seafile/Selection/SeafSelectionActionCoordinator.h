//
//  SeafSelectionActionCoordinator.h
//  seafile
//
//  Coordinates multi-selection: expand items, aggregate downloads,
//  unified progress HUD, media album save, and mixed-type sharing.
//

#import <UIKit/UIKit.h>

@class SeafBase, SeafFile;

NS_ASSUME_NONNULL_BEGIN

@interface SeafSelectionActionCoordinator : NSObject

- (instancetype)initWithHostViewController:(UIViewController *)hostViewController;

@property (nonatomic, readonly, getter=isAggregating) BOOL aggregating;
@property (nonatomic, readonly) BOOL unifiedAllMediaProgressActive;

- (void)handleSelectedItems:(NSArray<SeafBase *> *)items
                 sourceView:(UIView *)sourceView;

- (void)updateAggregateProgressForEntry:(SeafBase *)entry
                               progress:(float)progress;

// Optional: notify when a file finishes via delegate path (outside our block)
- (void)notifyFileDownloadCompleted:(SeafFile *)file
                              error:(NSError * _Nullable)error;

@end

NS_ASSUME_NONNULL_END


