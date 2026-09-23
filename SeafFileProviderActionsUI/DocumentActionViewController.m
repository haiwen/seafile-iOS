//
//  DocumentActionViewController.m
//  SeafFileProviderActionsUI
//
//  Created by three on 2020/7/19.
//  Copyright © 2020 Seafile. All rights reserved.
//

#import "DocumentActionViewController.h"
#import "SeafTheme.h"
#import <FileProvider/FileProvider.h>

// Mirrors SeafFPErrors in the File Provider extension.
static NSString * const kSeafFPErrorReasonKey = @"reason";
static NSString * const kSeafFPErrorReasonNoAccount = @"noAccount";
static NSString * const kSeafFPErrorReasonTouchIdEnabled = @"touchIdEnabled";

@interface DocumentActionViewController()
@property (weak) IBOutlet UILabel *identifierLabel;
@property (weak) IBOutlet UILabel *actionTypeLabel;
@end

@implementation DocumentActionViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [SeafTheme applyPreferenceToViewController:self];
}

- (void)prepareForActionWithIdentifier:(NSString *)actionIdentifier itemIdentifiers:(NSArray <NSFileProviderItemIdentifier> *)itemIdentifiers {
}

- (void)prepareForError:(NSError *)error {
    NSString *reason = error.userInfo[kSeafFPErrorReasonKey];
    BOOL providerError = [error.domain isEqualToString:NSFileProviderErrorDomain];
    if ([reason isEqualToString:kSeafFPErrorReasonNoAccount]) {
        self.identifierLabel.text = NSLocalizedString(@"There is no account available", @"Seafile");
        self.actionTypeLabel.text = NSLocalizedString(@"Please open Seafile and add an account to start", @"Seafile");
    } else if ([reason isEqualToString:kSeafFPErrorReasonTouchIdEnabled]) {
        // Normally such accounts have no domain; this is the window before the
        // app managed to remove it.
        self.identifierLabel.text = NSLocalizedString(@"Face ID / Touch ID is enabled", @"Seafile");
        self.actionTypeLabel.text = NSLocalizedString(@"Files cannot show this account while Face ID / Touch ID protection is on. Turn it off in Seafile to use the account here.", @"Seafile");
    } else if (providerError && error.code == NSFileProviderErrorNotAuthenticated) {
        self.identifierLabel.text = NSLocalizedString(@"Sign in to Seafile", @"Seafile");
        self.actionTypeLabel.text = NSLocalizedString(@"Your Seafile session has expired. Open Seafile, sign in again, then come back to Files.", @"Seafile");
    } else if (providerError && error.code == NSFileProviderErrorServerUnreachable) {
        self.identifierLabel.text = NSLocalizedString(@"Seafile server unreachable", @"Seafile");
        self.actionTypeLabel.text = NSLocalizedString(@"Check the network connection and try again.", @"Seafile");
    } else {
        self.identifierLabel.text = NSLocalizedString(@"Seafile is unavailable", @"Seafile");
        self.actionTypeLabel.text = error.localizedDescription ?: @"";
    }
}

- (IBAction)cancelButtonTapped:(id)sender {
    [self.extensionContext cancelRequestWithError:[NSError errorWithDomain:FPUIErrorDomain code:FPUIExtensionErrorCodeUserCancelled userInfo:nil]];
}

@end
