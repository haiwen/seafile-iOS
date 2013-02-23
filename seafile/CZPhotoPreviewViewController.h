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

#import <UIKit/UIKit.h>

@interface CZPhotoPreviewViewController : UIViewController

/**
 `CZPhotoPreviewViewController` shows an image to the user for review. It should act
 like the preview in Mail.app and Messages.app. It does not support pinch to zoom.

 @param anImage The `UIImage` to show. Will be presented aspect fit.
 @param chooseBlock Block to be called if choose/use button is tapped.
 @param cancelBlock Block to be called if they cancel.
 */
- (id)initWithImage:(UIImage *)anImage chooseBlock:(dispatch_block_t)chooseBlock cancelBlock:(dispatch_block_t)cancelBlock;

@end
