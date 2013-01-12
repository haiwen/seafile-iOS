//
//  SeafData.m
//  seafile
//
//  Created by Wei Wang on 7/25/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafData.h"


@implementation SeafServer

@dynamic url;
@dynamic username;
@dynamic content;

@end


@implementation StarredFiles

@dynamic url;
@dynamic username;
@dynamic content;

@end


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

@end
