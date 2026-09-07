//
//  SeafFPEnumerator.h
//  SeafFileProvider
//
//  Enumerates the domain root (library list), library / directory
//  containers, the working set and the (always empty) trash.
//

#import <Foundation/Foundation.h>
#import <FileProvider/FileProvider.h>

@class SeafFPExtension;

NS_ASSUME_NONNULL_BEGIN

@interface SeafFPEnumerator : NSObject <NSFileProviderEnumerator>

- (instancetype)initWithExtension:(SeafFPExtension *)extension
              containerIdentifier:(NSFileProviderItemIdentifier)containerIdentifier;

@end

NS_ASSUME_NONNULL_END
