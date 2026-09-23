//
//  SeafIconFont.m
//  seafilePro
//

#import "SeafIconFont.h"
#import <CoreText/CoreText.h>
#import "Debug.h"

/// Base name of both bundled resources: haiwen-iconfont.ttf and haiwen-iconfont.json.
/// Keep the two in sync when re-syncing the font from the Android client.
static NSString * const kIconFontResourceName = @"haiwen-iconfont";

@interface SeafIconFont ()
/// PostScript name the font registered under, or nil when registration failed.
@property (nonatomic, copy, nullable) NSString *fontName;
/// Glyph name -> single-character string. Immutable once built, so it can be read
/// from any thread.
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *glyphs;
@end

@implementation SeafIconFont

+ (instancetype)sharedInstance
{
    static SeafIconFont *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    if (self = [super init]) {
        _fontName = [self.class registerFont];
        _glyphs = [self.class loadGlyphTable];
    }
    return self;
}

#pragma mark - Public

- (UIFont *)fontOfSize:(CGFloat)size
{
    if (self.fontName.length == 0) return nil;
    return [UIFont fontWithName:self.fontName size:size];
}

- (NSString *)glyphForName:(NSString *)name
{
    if (name.length == 0) return nil;
    return self.glyphs[name];
}

#pragma mark - Loading

// Registers the bundled TTF for this process only. Doing it here rather than through
// Info.plist's UIAppFonts keeps the font out of every other target's launch path.
+ (nullable NSString *)registerFont
{
    NSString *path = [NSBundle.mainBundle pathForResource:kIconFontResourceName ofType:@"ttf"];
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    if (!data) {
        Warning("Icon font %@.ttf is missing from the bundle", kIconFontResourceName);
        return nil;
    }

    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGFontRef cgFont = provider ? CGFontCreateWithDataProvider(provider) : NULL;
    if (provider) CGDataProviderRelease(provider);
    if (!cgFont) {
        Warning("Failed to build a CGFont from %@.ttf", kIconFontResourceName);
        return nil;
    }

    CFErrorRef error = NULL;
    if (!CTFontManagerRegisterGraphicsFont(cgFont, &error)) {
        // Already being registered is not a failure: the font is usable either way.
        BOOL alreadyRegistered = (error != NULL && CFErrorGetCode(error) == kCTFontManagerErrorAlreadyRegistered);
        if (error) CFRelease(error);
        if (!alreadyRegistered) {
            Warning("Failed to register %@.ttf", kIconFontResourceName);
            CGFontRelease(cgFont);
            return nil;
        }
    }

    NSString *postScriptName = CFBridgingRelease(CGFontCopyPostScriptName(cgFont));
    CGFontRelease(cgFont);
    return postScriptName;
}

+ (NSDictionary<NSString *, NSString *> *)loadGlyphTable
{
    NSString *path = [NSBundle.mainBundle pathForResource:kIconFontResourceName ofType:@"json"];
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    if (!data) {
        Warning("Icon font table %@.json is missing from the bundle", kIconFontResourceName);
        return @{};
    }

    NSError *error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    NSArray *glyphs = [json isKindOfClass:NSDictionary.class] ? json[@"glyphs"] : nil;
    if (![glyphs isKindOfClass:NSArray.class]) {
        Warning("Failed to read glyphs from %@.json: %@", kIconFontResourceName, error);
        return @{};
    }

    NSMutableDictionary *table = [NSMutableDictionary dictionaryWithCapacity:glyphs.count];
    for (NSDictionary *glyph in glyphs) {
        if (![glyph isKindOfClass:NSDictionary.class]) continue;
        // "font_class" is the bare name the server sends; the "haiwen-" prefix in the
        // font's CSS is a stylesheet convention and is not part of the key.
        NSString *name = glyph[@"font_class"];
        NSNumber *codePoint = glyph[@"unicode_decimal"];
        if (![name isKindOfClass:NSString.class] || ![codePoint isKindOfClass:NSNumber.class]) continue;

        // Every glyph sits in the BMP private use area, so one UTF-16 unit is enough.
        NSUInteger value = codePoint.unsignedIntegerValue;
        if (value == 0 || value > 0xFFFF) continue;
        unichar unit = (unichar)value;
        table[name] = [NSString stringWithCharacters:&unit length:1];
    }
    return table;
}

@end
