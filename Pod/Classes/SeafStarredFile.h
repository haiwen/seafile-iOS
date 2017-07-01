//
//  SeafStarredFile.h
//  seafile
//
//  Created by Wang Wei on 11/4/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafFile.h"

@protocol SeafStarFileDelegate <NSObject>
- (void)fileStateChanged:(BOOL)starred file:(SeafFile *)sfile;
@end

@interface SeafStarredFile : SeafFile
@property (strong) id<SeafStarFileDelegate> starDelegate;
@property int org;


- (id)initWithConnection:(SeafConnection *)aConnection
                    repo:(NSString *)aRepo
                    path:(NSString *)aPath
                   mtime:(long long)mtime
                    size:(long long)size
                     org:(int)org
                     oid:(NSString *)anId;
@end
