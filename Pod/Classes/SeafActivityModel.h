//
//  SeafActivityModel.h
//  Seafile
//
//  Created by three on 2019/6/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
    Model for handling activity data in Seafile app, including user activities related to file operations.
 */
@interface SeafActivityModel : NSObject

/// Name of the user who performed the activity.
@property (nonatomic, copy) NSString *authorName;

/// Time when the activity occurred, formatted relative to the current time.
@property (nonatomic, copy) NSString *time;

/// Description of the operation performed, e.g., file added, renamed.
@property (nonatomic, copy) NSString *operation;

/// URL of the user's avatar.
@property (nonatomic, strong) NSURL *avatarURL;

/// Name of the repository where the activity took place.
@property (nonatomic, copy) NSString *repoName;

/// Detailed string about the activity, could include file names or paths changed.
@property (nonatomic, copy) NSString *detail;

/**
 * Initializes a SeafActivityModel with the JSON dictionary of the event and a map of operations.
 * @param event A dictionary containing keys and values related to the activity event.
 * @param opsMap A dictionary mapping operation types and object types to user-friendly operation descriptions.
 * @return An instance of SeafActivityModel populated with the data from the event and operations map.
 */
- (instancetype)initWithEventJSON:(NSDictionary *)event andOpsMap:(NSDictionary *)opsMap;

@end

NS_ASSUME_NONNULL_END
