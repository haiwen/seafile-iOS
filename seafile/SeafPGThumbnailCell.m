#import "SeafPGThumbnailCell.h"
#import "SeafPGThumbnailCellViewModel.h"

@interface SeafPGThumbnailCell ()
@property (nonatomic, strong, readwrite) UIImageView *thumbnailImageView;
@property (nonatomic, strong, readwrite) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, weak) SeafPGThumbnailCellViewModel *currentViewModel; // To manage callbacks
@end

@implementation SeafPGThumbnailCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    self.contentView.backgroundColor = [UIColor clearColor]; // Cell background

    self.thumbnailImageView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
    self.thumbnailImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.thumbnailImageView.clipsToBounds = YES;
    self.thumbnailImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.thumbnailImageView.layer.cornerRadius = 5.0;
    self.thumbnailImageView.layer.masksToBounds = YES;
    [self.contentView addSubview:self.thumbnailImageView];

    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingIndicator.hidesWhenStopped = YES;
    self.loadingIndicator.center = CGPointMake(self.contentView.bounds.size.width / 2, self.contentView.bounds.size.height / 2);
    self.loadingIndicator.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.contentView addSubview:self.loadingIndicator];
    
    // Remove default border/shadow styling from the old implementation if any was applied by default
    self.layer.borderWidth = 0;
    self.layer.cornerRadius = 0;
    self.clipsToBounds = YES;
    self.layer.shadowOpacity = 0;
}

- (void)configureWithViewModel:(SeafPGThumbnailCellViewModel *)viewModel {
    self.currentViewModel = viewModel;
    
    UIImage *imageToDisplay = viewModel.thumbnailImage ?: [UIImage imageNamed:@"gallery_placeholder.png"];
    self.thumbnailImageView.image = imageToDisplay;

    UIImage *failureImage = [UIImage imageNamed:@"gallery_failed.png"];
    if (imageToDisplay && [imageToDisplay isEqual:failureImage]) {
        self.thumbnailImageView.contentMode = UIViewContentModeScaleAspectFit;
    } else {
        self.thumbnailImageView.contentMode = UIViewContentModeScaleAspectFill;
    }

    if (viewModel.isLoading) {
        [self.loadingIndicator startAnimating];
    } else {
        [self.loadingIndicator stopAnimating];
    }
    
    // The ViewModel will handle the actual loading and then trigger an update.
    // The cell just needs to observe the ViewModel's onUpdate block.
    __weak typeof(self) weakSelf = self;
    viewModel.onUpdate = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.currentViewModel != viewModel) {
            // This cell is either deallocated or reused for a different ViewModel.
            return;
        }
        // Ensure UI updates are on the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            UIImage *updatedImageToDisplay = viewModel.thumbnailImage ?: [UIImage imageNamed:@"gallery_placeholder.png"];
            strongSelf.thumbnailImageView.image = updatedImageToDisplay;

            UIImage *failureImage = [UIImage imageNamed:@"gallery_failed.png"];
            if (updatedImageToDisplay && [updatedImageToDisplay isEqual:failureImage]) {
                strongSelf.thumbnailImageView.contentMode = UIViewContentModeScaleAspectFit;
            } else {
                strongSelf.thumbnailImageView.contentMode = UIViewContentModeScaleAspectFill;
            }

            if (viewModel.isLoading) {
                [strongSelf.loadingIndicator startAnimating];
            } else {
                [strongSelf.loadingIndicator stopAnimating];
            }
        });
    };
    
    // Ask the ViewModel to load data if needed
    [viewModel loadThumbnailIfNeeded];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    
    // Cancel any ongoing loading for the old ViewModel
    [self.currentViewModel cancelThumbnailLoad];
    self.currentViewModel.onUpdate = nil; // Clear the update block
    self.currentViewModel = nil;
    
    // Reset cell to a default state
    self.thumbnailImageView.image = nil;
    self.thumbnailImageView.contentMode = UIViewContentModeScaleAspectFill; // Reset content mode
    [self.loadingIndicator stopAnimating];
}

- (void)dealloc {
    // In case prepareForReuse wasn't called or to be absolutely sure
    [_currentViewModel cancelThumbnailLoad];
    _currentViewModel.onUpdate = nil;
}

@end 