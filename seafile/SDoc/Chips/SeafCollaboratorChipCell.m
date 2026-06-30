//  SeafCollaboratorChipCell.m
//  Now delegates visual rendering to the shared SeafCollaboratorChipView.

#import "SeafCollaboratorChipCell.h"
#import "SeafCollaboratorChipView.h"

@interface SeafCollaboratorChipCell ()
@property (nonatomic, strong) SeafCollaboratorChipView *chipView;
@end

@implementation SeafCollaboratorChipCell

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        _chipView = [[SeafCollaboratorChipView alloc] init];
        _chipView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_chipView];
        [NSLayoutConstraint activateConstraints:@[
            [_chipView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_chipView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [_chipView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_chipView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        ]];
    }
    return self;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [self.chipView configureWithName:@"" avatarURL:nil];
}

- (void)configureWithName:(NSString *)name avatarURL:(NSString *)avatarURL
{
    [self.chipView configureWithName:name avatarURL:avatarURL];
}

@end
