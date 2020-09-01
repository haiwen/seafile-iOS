//
//  DocumentActionViewController.m
//  SeafFileProviderActionsUI
//
//  Created by three on 2020/7/19.
//  Copyright © 2020 Seafile. All rights reserved.
//

#import "DocumentActionViewController.h"

@interface DocumentActionViewController()
@property (weak) IBOutlet UILabel *identifierLabel;
@property (weak) IBOutlet UILabel *actionTypeLabel;
@end

@implementation DocumentActionViewController

- (void)prepareForActionWithIdentifier:(NSString *)actionIdentifier itemIdentifiers:(NSArray <NSFileProviderItemIdentifier> *)itemIdentifiers {
}
    
- (void)prepareForError:(NSError *)error {
    NSDictionary *userInfo = error.userInfo;
    if (userInfo) {
        NSString *reason = [userInfo objectForKey:@"reason"];
        if ([reason isEqualToString:@"notAuthenticated"]) {
            self.identifierLabel.text = NSLocalizedString(@"FaceID(TouchID) is Enabled", @"Seafile");
            self.actionTypeLabel.text = NSLocalizedString(@"Files cannot access files in Seafile when FaceID(TouchID) enabled. Please open Seafile and disable FaceID(TouchID).", @"Seafile");
        } else if ([reason isEqualToString:@"noAccount"]) {
            self.identifierLabel.text = NSLocalizedString(@"There is no account available", @"Seafile");
            self.actionTypeLabel.text = NSLocalizedString(@"Please open Seafile ans add an account to start", @"Seafile");
        }
        
    }
}

//- (IBAction)doneButtonTapped:(id)sender {
//    // Perform the action and call the completion block. If an unrecoverable error occurs you must still call the completion block with an error. Use the error code FPUIExtensionErrorCodeFailed to signal the failure.
//    [self checkTouchId:^(bool success) {
//        [self.extensionContext completeRequest];
//    }];
//}
    
- (IBAction)cancelButtonTapped:(id)sender {
    [self.extensionContext cancelRequestWithError:[NSError errorWithDomain:FPUIErrorDomain code:FPUIExtensionErrorCodeUserCancelled userInfo:nil]];
}

@end

