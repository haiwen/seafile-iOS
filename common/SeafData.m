//
//  SeafData.m
//  seafile
//
//  Created by Wei Wang on 7/25/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafData.h"


@implementation Directory

@dynamic repoid;
@dynamic oid;
@dynamic path;
@dynamic content;

@end

@implementation DownloadedFile

@dynamic repoid;
@dynamic path;
@dynamic oid;
@dynamic mpath;

@end


@implementation SeafCacheObj

@dynamic url;
@dynamic username;
@dynamic key;
@dynamic content;
@dynamic timestamp;

@end

@implementation UploadedPhotos

@dynamic username;
@dynamic server;
@dynamic url;

@end
