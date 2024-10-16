//
//  SeafStarredFile.h
//  seafile
//
//  Created by Wang Wei on 11/4/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafFile.h"

/**
 * The `SeafStarFileDelegate` protocol defines methods that a delegate of a `SeafStarredFile` object
 * must adopt. The methods provide notifications for changes to the starred status of the file.
 */

/**
 * `SeafStarredFile` is a subclass of `SeafFile` that represents a file marked as starred in Seafile.
 */
@interface SeafStarredFile : SeafFile
@property int org;/// The organization identifier for this file, if it belongs to an organization library.
@property (nonatomic, assign) int isDir;//is file or dir

- (id)initWithConnection:(SeafConnection *)aConnection Info:(NSDictionary *)infoDict;

/**
 * Initializes a `SeafStarredFile` object with the specified parameters.
 * @param aConnection The connection to the Seafile server.
 * @param aRepo The repository identifier where the file is located.
 * @param aPath The path to the file within the repository.
 * @param mtime The modification time of the file.
 * @param size The size of the file in bytes.
 * @param org The organization identifier, if applicable.
 * @param anId The object identifier for the file.
 * @return An initialized `SeafStarredFile` object.
 */
//- (id)initWithConnection:(SeafConnection *)aConnection
//                    repo:(NSString *)aRepo
//                    path:(NSString *)aPath
//                   mtime:(long long)mtime
//                    size:(long long)size
//                     org:(int)org
//                     oid:(NSString *)anId;
@end
