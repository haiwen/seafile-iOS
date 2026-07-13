//
//  SeafShareBaseListViewController.h
//  SeafShare
//
//  Base class for Share Extension list-style destination pickers
//  (Recent tab, Starred tab, and future similar tabs).
//  Provides the common rounded-card tableView, empty-state label,
//  loading indicator, and single-select checkbox toggle logic.
//

#import <UIKit/UIKit.h>
@class SeafConnection;
@class SeafDir;
@class SeafShareDestCell;

/// Cell reuse identifier registered by the base class for SeafShareDestCell.
extern NSString * const kShareDestCellId;

@interface SeafShareBaseListViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong, readonly) SeafConnection *connection;
@property (nonatomic, strong, readonly) UITableView *tableView;
@property (nonatomic, strong, readonly) UILabel *emptyLabel;
@property (nonatomic, strong, readonly) UIActivityIndicatorView *loadingView;

/// Index of the currently selected row (-1 = no selection).
@property (nonatomic, assign) NSInteger selectedIndex;

- (instancetype)initWithConnection:(SeafConnection *)connection;

#pragma mark - Subclass hooks (override in subclasses)

/// Number of items in the data source. Default returns 0.
- (NSInteger)dataSourceCount;

/// Whether the item at the given index is selectable. Default returns YES.
- (BOOL)isItemSelectableAtIndex:(NSInteger)index;

/// Returns the currently selected directory, or nil. Subclass must override.
- (SeafDir *)selectedDirectory;

#pragma mark - Helpers for subclasses

/// Toggle checkbox single-selection at the given index path.
/// Handles deselecting the previous row and reloading affected cells.
- (void)handleSelectionAtIndexPath:(NSIndexPath *)indexPath inTableView:(UITableView *)tableView;

/// Show / hide the empty-state label with the given message.
/// Visibility is determined by `dataSourceCount == 0`.
- (void)updateEmptyStateWithMessage:(NSString *)message;

@end
