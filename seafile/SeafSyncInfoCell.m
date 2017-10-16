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

-(void)showCellWithFile:(id)file
{
    if ([file isKindOfClass:[SeafFile class]]) {
        SeafFile *dfile = (SeafFile*)file;
        dfile.delegate = self;
        
        self.nameLabel.text = dfile.name;
        self.pathLabel.text = dfile.fullPath;
        self.iconView.image = dfile.icon;
        self.sizeLabel.text = dfile.detailText;
        
        if (dfile.state == SEAF_DENTRY_INIT){
            self.progressView.hidden = YES;
            self.statusLabel.text = @"";
            self.sizeLabelLeftConstraint.constant = 0;
        } else if (dfile.state == SEAF_DENTRY_LOADING) {
            self.sizeLabelLeftConstraint.constant = 0;
            self.statusLabel.text = @"";
            if (dfile.progress.fractionCompleted == 1.0 || dfile.progress.fractionCompleted == 0.0) {
                self.progressView.hidden = YES;
            } else {
                self.progressView.hidden = NO;
            }
        } else if (dfile.state == SEAF_DENTRY_SUCCESS){
            self.progressView.hidden = YES;
            self.sizeLabelLeftConstraint.constant = 8;
            self.statusLabel.text = NSLocalizedString(@"Completed", @"Seafile");
        } else if (dfile.state == SEAF_DENTRY_FAILURE) {
            self.progressView.hidden = YES;
            self.statusLabel.text = NSLocalizedString(@"Failed", @"Seafile");
            self.sizeLabelLeftConstraint.constant = 8;
        }
    } else if ([file isKindOfClass:[SeafUploadFile class]]) {
        SeafUploadFile *ufile = (SeafUploadFile*)file;
        
        self.nameLabel.text = ufile.name;
        self.statusLabel.text = @"";
        self.iconView.image = ufile.icon;
        self.sizeLabel.text = [FileSizeFormatter stringFromLongLong:ufile.filesize];
        if (ufile.uploading) {
            self.progressView.hidden = NO;
            self.progressView.progress = ufile.uProgress/100.00;
            self.statusLabel.text = NSLocalizedString(@"Uploading", @"Seafile");
        } else {
            self.progressView.hidden = YES;
            self.statusLabel.text = NSLocalizedString(@"Completed", @"Seafile");
        }
    }
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
