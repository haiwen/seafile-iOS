//  SeafSdocProfileSheetViewController.h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SeafConnection;
@class SeafFileProfileAggregate;

@interface SeafSdocProfileSheetViewController : UIViewController

// rows: array of dictionaries from SeafSdocProfileAssembler (title/icon/type/values)
- (instancetype)initWithRows:(NSArray<NSDictionary *> *)rows;

/// Full initializer with editing support
/// @param rows Pre-assembled rows for display
/// @param connection Connection for API calls (needed for editor)
/// @param repoId Repository ID
/// @param aggregate Raw aggregate data (passed to editor for editing)
/// @param metadataEnabled Whether metadata is enabled (controls edit button visibility)
- (instancetype)initWithRows:(NSArray<NSDictionary *> *)rows
                  connection:(nullable SeafConnection *)connection
                      repoId:(nullable NSString *)repoId
                   aggregate:(nullable SeafFileProfileAggregate *)aggregate
             metadataEnabled:(BOOL)metadataEnabled;

@end

NS_ASSUME_NONNULL_END


