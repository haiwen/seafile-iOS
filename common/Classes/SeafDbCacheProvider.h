//
//  NSObject+SeafDbCacheProvider.h
//  Pods
//
//  Created by Wei W on 4/8/17.
//
//

#import <Foundation/Foundation.h>
#import "SeafCacheProvider.h"


@interface SeafDbCacheProvider: NSObject<SeafCacheProvider>

- (void)migrateUploadedPhotos:(NSString *)url username:(NSString *)username account:(NSString *)account;

@end
