//
//  SeafAvatarOperation.h
//  Pods
//
//  Created by henry on 2024/11/11.
//
#import <Foundation/Foundation.h>

@class SeafAvatar;

/**
 * SeafAvatarOperation handles the network operations for downloading avatars.
 */
@interface SeafAvatarOperation : NSOperation

@property (nonatomic, strong) SeafAvatar *avatar;

- (instancetype)initWithAvatar:(SeafAvatar *)avatar;

@end

