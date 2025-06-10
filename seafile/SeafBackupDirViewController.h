//
//  SeafBackupDirViewController.h
//  seafile
//
//  Created by Henry on 2025/6/9.
//  Copyright © 2024 Seafile Ltd. All rights reserved.
//

#import "SeafDirViewController.h"

@class SeafRepo;

NS_ASSUME_NONNULL_BEGIN

@interface SeafBackupDirViewController : SeafDirViewController

@property (nonatomic, weak) SeafRepo *selectedRepo;

@end

NS_ASSUME_NONNULL_END 
