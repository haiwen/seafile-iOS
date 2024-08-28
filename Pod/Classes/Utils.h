//
//  Utils.h
//  seafile
//
//  Created by Wang Wei on 10/13/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <UIKit/UIKit.h>

/// Maximum dimension for image processing.
#define IMAGE_MAX_SIZE 2048

/**
    Utility class for file and directory management, image processing, JSON encoding/decoding, and user interface alerts in the Seafile app.
 */
@interface Utils : NSObject

/// Check if a file exists at a given path.
+ (BOOL)fileExistsAtPath:(NSString *)path;

/// Ensure a directory exists at a specified path, creating it if necessary.
+ (BOOL)checkMakeDir:(NSString *)path;

/// Clear all files within a specified directory.
+ (void)clearAllFiles:(NSString *)path;

/// Remove a file at a specified path.
+ (BOOL)removeFile:(NSString *)path;

/// Remove a directory only if it is empty.
+ (void)removeDirIfEmpty:(NSString *)path;

/// Calculate the size of the folder at a given path.
+ (long long)folderSizeAtPath:(NSString*)folderPath;

/// Copy a file from a URL to another URL.
+ (BOOL)copyFile:(NSURL *)from to:(NSURL *)to;

/// Create a hard link from one URL to another.
+ (BOOL)linkFileAtURL:(NSURL *)from to:(NSURL *)to error:(NSError **)error;

/// Create a hard link from one file path to another.
+ (BOOL)linkFileAtPath:(NSString *)from to:(NSString *)to error:(NSError **)error;

/// Write image data with metadata to a specified path.
+ (BOOL)writeDataWithMeta:(NSData *)imageData toPath:(NSString*)filePath;

/// Write a CIImage to a file path, available from iOS 10.
+ (BOOL)writeCIImage:(CIImage *)ciImage toPath:(NSString*)filePath API_AVAILABLE(ios(10.0));

/// Get the size of a file at a specific path.
+ (long long)fileSizeAtPath1:(NSString*)filePath;

/// Attempt to transform encoding of a file content to another file.
+ (BOOL)tryTransformEncoding:(NSString *)outfile fromFile:(NSString *)fromfile;

/// Get string content from a file at a specified path.
+ (NSString *)stringContent:(NSString *)path;

/// Encode an object into JSON data.
+ (NSData *)JSONEncode:(id)obj;

/// Decode JSON data into an object.
+ (id)JSONDecode:(NSData *)data error:(NSError **)error;

/// Encode a dictionary into a JSON string.
+ (NSString *)JSONEncodeDictionary:(NSDictionary *)dict;

/// Check if a filename indicates an image file.
+ (BOOL)isImageFile:(NSString *)name;

/// Check if a filename indicates a video file.
+ (BOOL)isVideoFile:(NSString *)name;

/// Check if a file extension is that of a video file.
+ (BOOL)isVideoExt:(NSString *)ext;

/// Calculate the display size of text given specific constraints.
+ (CGSize)textSizeForText:(NSString *)txt font:(UIFont *)font width:(float)width;

/// Display an alert with a title, message, and "Yes" "No" options.
+ (void)alertWithTitle:(NSString *)title message:(NSString*)message yes:(void (^)(void))yes no:(void (^)(void))no from:(UIViewController *)c;

/// Display an alert with a title, message, and dismissal handler.
+ (void)alertWithTitle:(NSString *)title message:(NSString*)message handler:(void (^)(void))handler from:(UIViewController *)c;

/// Display a popup to input text with a title and placeholder.
+ (void)popupInputView:(NSString *)title placeholder:(NSString *)tip inputs:(NSString *)inputs secure:(BOOL)secure handler:(void (^)(NSString *input))handler from:(UIViewController *)c;

/// Generate an alert controller with options.
+ (UIAlertController *)generateAlert:(NSArray *)arr withTitle:(NSString *)title handler:(void (^)(UIAlertAction *action))handler cancelHandler:(void (^)(UIAlertAction *action))cancelHandler preferredStyle:(UIAlertControllerStyle)preferredStyle;

/// Resize an image to fit within a specified square dimension.
+ (UIImage *)reSizeImage:(UIImage *)image toSquare:(float)length;
/// Load an image from a path, optionally using a cache.
+ (UIImage *)imageFromPath:(NSString *)path withMaxSize:(float)length cachePath:(NSString *)cachePath;

/// Convert a query string to a dictionary of parameters.
+ (NSDictionary *)queryToDict:(NSString *)query;

/// Set an object in a dictionary safely.
+ (void)dict:(NSMutableDictionary *)dict setObject:(id)value forKey:(NSString *)defaultName;

/// Encode a path with components.
+ (NSString *)encodePath:(NSString *)server username:(NSString *)username repo:(NSString *)repoId path:(NSString *)path;

/// Decode a path into its components.
+ (void)decodePath:(NSString *)encodedStr server:(NSString **)server username:(NSString **)username repo:(NSString **)repoId path:(NSString **)path;

/// Generate a default error object.
+ (NSError *)defaultError;

/// Convert a file URL and identifier to an ALAsset URL.
+ (NSString *)convertToALAssetUrl:(NSString *)fileURL andIdentifier:(NSString *)identifier;

/// Generate a temporary file path for a given filename.
+ (NSURL *)generateFileTempPath:(NSString *)name;

/// Get the current bundle identifier.
+ (NSString *)currentBundleIdentifier;

/// Create a new filename by appending a sequence number.
+ (NSString *)creatNewFileName:(NSString *)fileName;

/// Check if is new version.
+ (BOOL)needsUpdateCurrentVersion:(NSString *)currentVersion newVersion:(NSString *)newVersion;

//convert dateString to UTC int
+ (int)convertTimeStringToUTC:(NSString *)timeStr;

@end
