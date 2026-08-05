//
//  IntelligentSplitViewController.m
//  From TexLege by Gregory S. Combs
//
//  Released under the Creative Commons Attribution 3.0 Unported License
//  Please see the included license page for more information.
//
//  In a nutshell, you can use this, just attribute this to me in your "thank you" notes or about box.
//

#import "IntelligentSplitViewController.h"

@implementation IntelligentSplitViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // A split view sitting in a background tab gets no size transition while it is
    // hidden, so its display mode has to be re-derived when it comes back on screen.
    [self updatePreferredDisplayModeForSize:self.view.bounds.size];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [self updatePreferredDisplayModeForSize:size];
}

- (void)updatePreferredDisplayModeForSize:(CGSize)size {
    self.preferredDisplayMode = (size.width > size.height)
        ? UISplitViewControllerDisplayModeOneBesideSecondary
        : UISplitViewControllerDisplayModeSecondaryOnly;
}

@end
