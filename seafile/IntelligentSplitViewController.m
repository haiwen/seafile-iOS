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
#import <objc/message.h>

@implementation IntelligentSplitViewController

- (id) init {
    if ((self = [super init])) {
        NSLog(@"IntelligentSplitViewController using init: and not using a NIB.");
        // I've actually never attempted to use this class without NIBs, but this should work.

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(willRotate:)
                                                     name:UIApplicationWillChangeStatusBarOrientationNotification object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didRotate:)
                                                     name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    //debug_NSLog(@"IntelligentSplitViewController awaking from a NIB: %@", self.title);

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(willRotate:)
                                                 name:UIApplicationWillChangeStatusBarOrientationNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didRotate:)
                                                 name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];

}

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
    [super viewDidLoad];
    //debug_NSLog(@"IntelligentSplitViewController loaded: %@", self.title);
}

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
}

- (void)viewDidUnload {
    //debug_NSLog(@"IntelligentSplitViewController unloaded: %@", self.title);

    [super viewDidUnload];
}


- (void)dealloc {
    @try {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
    @catch (NSException * e) {
        NSLog(@"IntelligentSplitViewController DE-OBSERVING CRASHED: %@ ... error:%@", self.title, [e description]);
    }

    [super dealloc];
}


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Overriden to allow any orientation.
    return YES;
}


- (void)willRotate:(id)sender {
    if (![self isViewLoaded]) // we haven't even loaded up yet, let's turn away from this place
        return;

    NSNotification *notification = sender;
    if (!notification)
        return;

    UIInterfaceOrientation toOrientation = [[notification.userInfo valueForKey:UIApplicationStatusBarOrientationUserInfoKey] integerValue];
    //UIInterfaceOrientation fromOrientation = [UIApplication sharedApplication].statusBarOrientation;

    UITabBarController *tabBar = self.tabBarController;
    BOOL notModal = (!tabBar.presentedViewController );
    BOOL isSelectedTab = [self.tabBarController.selectedViewController isEqual:self];

    NSTimeInterval duration = [[UIApplication sharedApplication] statusBarOrientationAnimationDuration];


    if (!isSelectedTab || !notModal)  {
        // Looks like we're not "visible" ... propogate rotation info
        [super willRotateToInterfaceOrientation:toOrientation duration:duration];

        UIViewController *master = [self.viewControllers objectAtIndex:0];
        NSObject<UISplitViewControllerDelegate> *theDelegate = (NSObject<UISplitViewControllerDelegate> *)self.delegate;


#define YOU_DONT_FEEL_QUEAZY_ABOUT_THIS_BECAUSE_IT_PASSES_THE_APP_STORE 0

#if YOU_DONT_FEEL_QUEAZY_ABOUT_THIS_BECAUSE_IT_PASSES_THE_APP_STORE
        UIBarButtonItem *button = [super valueForKey:@"_barButtonItem"];

#else //YOU_DO_FEEL_QUEAZY_AND_FOR_SOME_REASON_YOU_PREFER_THE_LESSER_EVIL_____FRIGHTENING_STUFF
        UIBarButtonItem *button = [[[[[self.viewControllers objectAtIndex:1]
                                      viewControllers] objectAtIndex:0]
                                    navigationItem] rightBarButtonItem];
#endif

        if (UIInterfaceOrientationIsPortrait(toOrientation)) {
            if (theDelegate && [theDelegate respondsToSelector:@selector(splitViewController:willHideViewController:withBarButtonItem:forPopoverController:)]) {

                @try {
                    UIPopoverController *popover = [super valueForKey:@"_hiddenPopoverController"];
                    [theDelegate splitViewController: self willHideViewController:master withBarButtonItem:button forPopoverController:popover];
                }
                @catch (NSException * e) {
                    NSLog(@"There was a nasty error while notifyng splitviewcontrollers of an orientation change: %@", [e description]);
                }
            }
        }
        else if (UIInterfaceOrientationIsLandscape(toOrientation)) {
            if (theDelegate && [theDelegate respondsToSelector:@selector(splitViewController:willShowViewController:invalidatingBarButtonItem:)]) {
                @try {
                    [theDelegate splitViewController:self willShowViewController:master invalidatingBarButtonItem:button];
                }
                @catch (NSException * e) {
                    NSLog(@"There was a nasty error while notifyng splitviewcontrollers of an orientation change: %@", [e description]);
                }
            }
        }
    }

    //debug_NSLog(@"MINE WillRotate ---- sender = %@  to = %d   from = %d", [sender class], toOrientation, fromOrientation);
}

/*
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    //debug_NSLog(@"Theirs --- will rotate");
}
*/

- (void)didRotate:(id)sender {
    if (![self isViewLoaded]) // we haven't even loaded up yet, let's turn away from this place
        return;

    NSNotification *notification = sender;
    if (!notification)
        return;
    UIInterfaceOrientation fromOrientation = [[notification.userInfo valueForKey:UIApplicationStatusBarOrientationUserInfoKey] integerValue];
    //UIInterfaceOrientation toOrientation = [UIApplication sharedApplication].statusBarOrientation;

    UITabBarController *tabBar = self.tabBarController;
    BOOL notModal = (!tabBar.presentedViewController );
    BOOL isSelectedTab = [self.tabBarController.selectedViewController isEqual:self];

    if (!isSelectedTab || !notModal)  {
        // Looks like we're not "visible" ... propogate rotation info
        [super didRotateFromInterfaceOrientation:fromOrientation];
    }

    //debug_NSLog(@"MINE DidRotate ---- sender = %@  from = %d   to = %d", [sender class], fromOrientation, toOrientation);
}

/*
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    //debug_NSLog(@"Theirs --- did rotate");
}
*/

@end
