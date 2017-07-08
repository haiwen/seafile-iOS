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

-(void)showCellWithSFile:(SeafFile *)sfile
{
    sfile.delegate = self;

    self.nameLabel.text = sfile.name;
    self.pathLabel.text = sfile.dirPath;
    self.iconView.image = sfile.icon;
    self.sizeLabel.text = sfile.detailText;

    if (sfile.state == SEAF_DENTRY_INIT){
        self.progressView.hidden = YES;
        self.statusLabel.text = @"";
        self.sizeLabelLeftConstraint.constant = 0;
    } else if (sfile.state == SEAF_DENTRY_LOADING) {
        self.progressView.hidden = NO;
        self.sizeLabelLeftConstraint.constant = 0;
        if (sfile.progress.fractionCompleted == 1.0) {
            self.progressView.hidden = YES;
        } else {
            self.progressView.hidden = NO;
            self.statusLabel.text = @"";
        }
    } else if (sfile.state == SEAF_DENTRY_SUCCESS){
        self.progressView.hidden = YES;
        self.sizeLabelLeftConstraint.constant = 8;
        self.statusLabel.text = NSLocalizedString(@"Completed", @"Seafile");
    } else if (sfile.state == SEAF_DENTRY_FAILURE) {
        self.progressView.hidden = YES;
        self.statusLabel.text = NSLocalizedString(@"Failed", @"Seafile");
        self.sizeLabelLeftConstraint.constant = 8;
    }
}

-(void)showCellWithUploadFile:(SeafUploadFile *)ufile
{
    self.nameLabel.text = ufile.name;
    self.statusLabel.text = @"";
    self.iconView.image = ufile.icon;
    self.sizeLabel.text = [FileSizeFormatter stringFromLongLong:ufile.filesize];

    @weakify(self);
    ufile.progressBlock = ^(SeafUploadFile *file, int progress) {
        @strongify(self);
        self.progressView.progress = progress/100.00;
    };

    ufile.completionBlock = ^(BOOL success, SeafUploadFile *file, NSString *oid) {
        @strongify(self);
        if (success) {
            self.progressView.hidden = YES;
            self.statusLabel.text = NSLocalizedString(@"Completed", @"Seafile");
        } else {
            self.progressView.hidden = NO;
            self.statusLabel.text = NSLocalizedString(@"uploading", @"Seafile");
        }
    };
}

#pragma mark - SeafDentryDelegate
- (void)download:(SeafBase *)entry progress:(float)progress
{
    Debug(@"%f", progress);
    self.progressView.progress = progress;
}

- (void)download:(SeafBase *)entry complete:(BOOL)updated
{

}

- (void)download:(SeafBase *)entry failed:(NSError *)error
{

}

-(void)awakeFromNib
{
    [super awakeFromNib];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
