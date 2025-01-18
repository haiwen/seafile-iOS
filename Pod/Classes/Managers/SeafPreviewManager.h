#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class SeafUploadFile;

@interface SeafPreviewManager : NSObject

- (NSURL *)previewURLForFile:(SeafUploadFile *)file;
- (NSURL *)exportURLForFile:(SeafUploadFile *)file;
- (UIImage *)iconForFile:(SeafUploadFile *)file;
- (UIImage *)thumbForFile:(SeafUploadFile *)file;
- (void)getImageWithFile:(SeafUploadFile *)file completion:(void (^)(UIImage *image))completion;

@end 