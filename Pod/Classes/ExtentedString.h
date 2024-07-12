//
//  EscapedString.h
//  seafile
//
//  Created by Wang Wei on 9/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
/**
    Extension of the NSString class to add methods for escaping strings and other utility functions.
 */
@interface NSString (ExtentedString)

/**
 * Escapes path component of a URL, preserving the base URL if present.
 * @return A new string where the path component is escaped.
 */
- (NSString *)escapedUrlPath;

/**
 * Escapes characters in a string creating a valid URL.
 * @return A new string with characters that are not URL friendly escaped.
 */
- (NSString *)escapedUrl;

/**
 * Escapes characters in a string for use in HTTP POST forms which is the same as URL encoding.
 * @return A new string with characters suitable for HTTP form posting.
 */
- (NSString *)escapedPostForm;

/**
 * Removes common URL prefixes from the string.
 * @return A new string with common URL prefixes like 'http://', 'https://' removed.
 */
- (NSString *)trimUrl;

/**
 * Checks if the string can be used as a valid file name.
 * @return YES if the string is a valid filename, otherwise NO.
 */
- (BOOL)isValidFileName;

/**
 * Escapes characters in a string to be safely included in JavaScript code.
 * @return A new JavaScript-escaped string.
 */
- (NSString *)stringEscapedForJavasacript;

/**
 * Finds the index of the first occurrence of a character in the string.
 * @param searchChar The character to search for.
 * @return The index of the character if found, or NSNotFound if not found.
 */
- (unsigned long) indexOf:(char) searchChar;

@end
