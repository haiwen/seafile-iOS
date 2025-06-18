//
//  SeafBackupGuideViewController.h
//  seafile
//
//  Created by Henry on 2025/6/9.
//  Copyright © 2024 Seafile Ltd. All rights reserved.
//

#import <UIKit/UIKit.h>

@class SeafConnection, SeafDir, SeafRepo, SeafBackupGuideViewController;

@protocol SeafBackupGuideDelegate <NSObject>
- (void)backupGuide:(SeafBackupGuideViewController *)guideVC didFinishWithRepo:(SeafRepo *)repo;
- (void)backupGuideDidCancel:(SeafBackupGuideViewController *)guideVC;
@end

@interface SeafBackupGuideViewController : UIViewController

@property (nonatomic, weak) id<SeafBackupGuideDelegate> delegate;
@property (strong, nonatomic) SeafConnection *connection;

- (instancetype)initWithConnection:(SeafConnection *)connection;

@end 
