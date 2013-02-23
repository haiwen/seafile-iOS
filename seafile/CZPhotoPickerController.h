// Copyright 2013 Care Zone Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef void (^CZPhotoPickerCompletionBlock)(UIImagePickerController *imagePickerController, NSDictionary *imageInfoDict);

@interface CZPhotoPickerController : NSObject

/**
 Defaults to NO. Is passed to the UIImagePickerController
 */
@property(nonatomic,assign) BOOL allowsEditing;

/**
 Allow overriding of the UIPopoverController class used to host the
 UIImagePickerController. Defaults to UIPopoverController.
 */
@property(nonatomic,copy) Class popoverControllerClass;

/**
 @param completionBlock Called when a photo has been picked or cancelled (`imageInfoDict` will be nil if canceled). The `UIImagePickerController` has not been dismissed at the time of this being called.
 */
- (id)initWithPresentingViewController:(UIViewController *)aViewController withCompletionBlock:(CZPhotoPickerCompletionBlock)completionBlock;

- (void)showFromBarButtonItem:(UIBarButtonItem *)barButtonItem;
- (void)showFromRect:(CGRect)rect;

@end
