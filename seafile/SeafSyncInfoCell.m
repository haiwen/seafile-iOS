//
//  SeafSyncInfoCell.m
//  seafilePro
//
//  Created by three on 2017/8/1.
//  Copyright © 2017年 Seafile. All rights reserved.
//

#import "SeafSyncInfoCell.h"
#import "Debug.h"
#import "FileSizeFormatter.h"

@interface SeafSyncInfoCell ()
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *sizeLabelLeftConstraint;

@end

@implementation SeafSyncInfoCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.iconView.clipsToBounds = YES;
        self.iconView.contentMode = UIViewContentModeScaleAspectFit;
        self.progressView.hidden = YES;
        // Initialization code
    }
    return self;
}

- (void)updateCellStatus:(id<SeafTask> _Nonnull)task
{
    if ([task isKindOfClass:[SeafFile class]]) {
        SeafFile *dfile = (SeafFile*)task;

        self.nameLabel.text = dfile.name;
        self.pathLabel.text = dfile.fullPath;
        self.iconView.image = dfile.icon;
        self.sizeLabel.text = dfile.detailText;
        self.progressView.hidden = YES;

        if (dfile.state == SEAF_DENTRY_INIT){
            self.statusLabel.text = @"";
            self.sizeLabelLeftConstraint.constant = 0;
        } else if (dfile.state == SEAF_DENTRY_LOADING) {
            self.sizeLabelLeftConstraint.constant = 0;
            self.statusLabel.text = @"";
            self.progressView.hidden = NO;
        } else if (dfile.state == SEAF_DENTRY_SUCCESS){
            self.sizeLabelLeftConstraint.constant = 8;
            self.statusLabel.text = NSLocalizedString(@"Completed", @"Seafile");
        } else if (dfile.state == SEAF_DENTRY_FAILURE) {
            self.statusLabel.text = NSLocalizedString(@"Failed", @"Seafile");
            self.sizeLabelLeftConstraint.constant = 8;
        }
    } else if ([task isKindOfClass:[SeafUploadFile class]]) {
        SeafUploadFile *ufile = (SeafUploadFile*)task;

        self.nameLabel.text = ufile.name;
        self.iconView.image = ufile.icon;
        self.statusLabel.text = @"";
        self.progressView.hidden = YES;
        if (ufile.isUploading) {
            self.progressView.hidden = NO;
            self.progressView.progress = ufile.uProgress;
            self.statusLabel.text = NSLocalizedString(@"Uploading", @"Seafile");
            self.sizeLabel.text = [FileSizeFormatter stringFromLongLong:ufile.filesize];
        } else if (ufile.uploaded) {
            self.statusLabel.text = NSLocalizedString(@"Completed", @"Seafile");
            self.sizeLabel.text = [FileSizeFormatter stringFromLongLong:ufile.filesize];
        } else {
            self.statusLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Waiting to upload", @"Seafile"), @""];
        }
    }
}

- (void)showCellWithTask:(id<SeafTask> _Nonnull)task {
    [self updateCellStatus:task];
    [task setTaskProgressBlock:^(id<SeafTask>  _Nonnull task, float progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressView.progress = progress;
        });
    }];
}

@end
