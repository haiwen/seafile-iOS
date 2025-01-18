#import <Foundation/Foundation.h>
#import "SeafFileModel.h"

@interface SeafFileFactory : NSObject

+ (SeafFile *)createSeafFileWithModel:(SeafFileModel *)model
                         connection:(SeafConnection *)connection;

+ (SeafFile *)createSeafFileWithOid:(NSString *)oid
                            repoId:(NSString *)repoId
                             name:(NSString *)name
                             path:(NSString *)path
                            mtime:(long long)mtime
                             size:(unsigned long long)size
                       connection:(SeafConnection *)connection;

@end 
