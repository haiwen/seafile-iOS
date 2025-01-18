#import "SeafFile.h"
#import "SeafFileFactory.h"
#import "SeafFileManager.h"
#import "SeafFileModel.h"
#import "SeafCacheManager.h"
#import "SeafFileStateManager.h"

@implementation SeafFileFactory

+ (SeafFile *)createSeafFileWithModel:(SeafFileModel *)model
                         connection:(SeafConnection *)connection {
    return [[SeafFile alloc] initWithModel:model connection:connection];
}

+ (SeafFile *)createSeafFileWithOid:(NSString *)oid
                            repoId:(NSString *)repoId
                             name:(NSString *)name
                             path:(NSString *)path
                            mtime:(long long)mtime
                             size:(unsigned long long)size
                       connection:(SeafConnection *)connection {
    
    SeafFileModel *model = [[SeafFileModel alloc] initWithOid:oid
                                                      repoId:repoId
                                                       name:name
                                                       path:path
                                                      mtime:mtime
                                                         size:size connection:connection];
    
    return [self createSeafFileWithModel:model connection:connection];
}

@end 
