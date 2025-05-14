//
//  EscapedString.m
//  seafile
//
//  Created by Wang Wei on 9/7/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "ExtentedString.h"
#import "Debug.h"

@implementation NSString (ExtentedString)

- (NSString *)escapedUrl
{
    return (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes
                                         (
                                          NULL,
                                          (__bridge CFStringRef)self,
                                          NULL,
                                          (CFStringRef)@"!*'();:@&=+$,?%#[]",
                                          kCFStringEncodingUTF8));
}

- (NSString *)escapedPostForm
{
    return [self escapedUrl];
}

#define HTTP @"http://"
#define HTTPS @"https://"
#define WWW @"http://www."
#define WWWS @"https://www."

- (NSString *)escapedUrlPath
{
    NSString *prefix, *path;
    if ([self hasPrefix:HTTP]) {
        prefix = HTTP;
        path = [self substringFromIndex:HTTP.length];
    } else if ([self hasPrefix:HTTPS]) {
        prefix = HTTPS;
        path = [self substringFromIndex:HTTPS.length];
    } else
        return self.escapedUrl;
    return [prefix stringByAppendingString:path.escapedUrl];
}

- (NSString *)trimUrl
{
    NSString *url = [self lowercaseString];

    if ([self hasPrefix:WWW]) {
        return [url substringFromIndex:WWW.length];
    } else if ([self hasPrefix:HTTP]) {
        return [url substringFromIndex:HTTP.length];
    } else if ([self hasPrefix:WWWS]) {
        return [url substringFromIndex:WWWS.length];
    } else if ([self hasPrefix:HTTPS]) {
        return [url substringFromIndex:HTTPS.length];
    }
    return url;
}


- (BOOL)isValidFileName
{
    if (self.length == 0)
        return NO;
    NSCharacterSet* illegalFileNameCharacters = [NSCharacterSet characterSetWithCharactersInString:@"\\/:"];
    NSRange range = [self rangeOfCharacterFromSet:illegalFileNameCharacters];
    if (range.location == NSNotFound)
        return YES;
    return NO;
}

- (NSString *)stringEscapedForJavasacript
{
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@[self] options:0 error:&error];
    if (error || !jsonData) {
        Debug(@"Error serializing string for javascript escaping: %@", error);
        return @"";
    }
    
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    if (!jsonString || jsonString.length < 4) {
        return jsonString;
    }
    
    NSString* escapedString = [jsonString substringWithRange:NSMakeRange(2, jsonString.length - 4)];
    
    return escapedString;
}

- (unsigned long)indexOf:(char) searchChar
{
    NSRange searchRange;
    searchRange.location = (unsigned int)searchChar;
    searchRange.length = 1;
    NSRange foundRange = [self rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:searchRange]];
    return foundRange.location;
}

@end
