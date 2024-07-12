//
//  SeafPreView.h
//  seafilePro
//
//  Created by Wang Wei on 8/3/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuickLook/QuickLook.h>

@class SeafBase;

/**
 Enumerates the possible return values for setting a repository's password.
 */
enum SET_REPO_PASSWORD_RET {
    RET_SUCCESS,
    RET_WRONG_PASSWORD,
    RET_FAILED,
};

/**
 Protocol for receiving the result of a repository password setting attempt.
 */
@protocol SeafRepoPasswordDelegate <NSObject>
/**
 Called when the repository password setting operation completes.
 @param entry The SeafBase entry where the operation was attempted.
 @param ret The result of the operation, as defined in `SET_REPO_PASSWORD_RET`.
 */
- (void)entry:(SeafBase *)entry repoPasswordSet:(int)ret;
@end

/**
 Protocol defining download-related delegate methods.
 */
@protocol SeafDentryDelegate
- (void)download:(SeafBase *)entry progress:(float)progress;///< Notifies delegate of download progress.
- (void)download:(SeafBase *)entry complete:(BOOL)updated;///< Notifies delegate when download is complete.
- (void)download:(SeafBase *)entry failed:(NSError *)error;///< Notifies delegate when download fails.
@end

/**
 Protocol for objects that are sortable based on their attributes.
 */
@protocol SeafSortable <NSObject>
- (NSString *)name;///< Returns the name of the object.
- (long long)mtime; ///< Returns the modification time of the object.
@end

/**
 Protocol defining the functionality required for previewing Seafile entries.
 */
@protocol SeafPreView <QLPreviewItem, SeafSortable>
- (UIImage *)image;///<  the image representation.
- (UIImage *)thumb;///< the thumbnail representation.
- (UIImage *)icon;///< the icon representation.
- (NSURL *)exportURL;///< the URL for exporting the file.
- (NSString *)mime;///< Returns the MIME type of the file.
- (BOOL)editable;///< Indicates whether the file is editable.
- (long long )filesize;///< Indicates whether the file is editable.
- (NSString *)strContent;///< Returns the string content of the file.
- (BOOL)saveStrContent:(NSString *)content;///< Saves the string content to the file.
- (BOOL)hasCache;///< Indicates whether the file is cached.
- (BOOL)isImageFile;///< Indicates whether the file is an image.
- (long long) mtime;///< the modification time of the file.
- (void)cancelAnyLoading;///< Cancels any ongoing loading processes.
- (void)setDelegate:(id)delegate; ///< Sets the delegate to receive callbacks.


- (void)load:(id<SeafDentryDelegate>)delegate force:(BOOL)force;///< Loads the file, optionally forcing a reload.
@end
