//
//  FileProvider.h
//  SeafFileProvider
//
//  Created by Wang Wei on 11/15/14.
//  Copyright (c) 2014 Seafile. All rights reserved.
//

#import <FileProvider/FileProvider.h>

@interface FileProvider : NSFileProviderExtension
@property (nonatomic, strong) NSCache *identifierCache;  // Used to cache the mapping from URL to identifier
@property (nonatomic, strong) NSCache *itemCache;        // Used to cache the mapping from identifier to SeafProviderItem
@end
