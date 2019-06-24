//
//  SeafActivitiesCell.h
//  seafileApp
//
//  Created by three on 2019/6/9.
//  Copyright © 2019 Seafile. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeafActivitiesCell : UITableViewCell

@property (strong, nonatomic) IBOutlet UIImageView *accountImageView;

@property (strong, nonatomic) IBOutlet UILabel *authorLabel;

@property (strong, nonatomic) IBOutlet UILabel *operationLabel;

@property (strong, nonatomic) IBOutlet UIView *operationContainer;

@property (strong, nonatomic) IBOutlet UILabel *desLabel;

@property (strong, nonatomic) IBOutlet UILabel *timeLabel;

@property (strong, nonatomic) IBOutlet UILabel *repoNameLabel;

- (void)showWithImage:(NSURL *)imageURL author:(NSString *)author operation:(NSString *)operation time:(NSString *)time detail:(NSString *)detail repoName:(NSString *)repoName;

@end

NS_ASSUME_NONNULL_END
