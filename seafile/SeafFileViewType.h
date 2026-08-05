//
//  SeafFileViewType.h
//  seafile
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SeafFileViewType) {
    SeafFileViewTypeList = 0,
    SeafFileViewTypeGrid = 1,
};

static NSString * const kSeafFileBrowseGridModeEnabled = @"kSeafFileBrowseGridModeEnabled";

NS_INLINE BOOL SeafFileBrowseGridModeEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kSeafFileBrowseGridModeEnabled];
}

NS_INLINE void SeafFileBrowseSetGridModeEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kSeafFileBrowseGridModeEnabled];
}

NS_ASSUME_NONNULL_END
