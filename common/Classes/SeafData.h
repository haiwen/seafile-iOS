//
//  SeafData.h
//  seafile
//
//  Created by Wei Wang on 7/25/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@interface SeafCacheObjV2 : NSManagedObject

@property (nonatomic, retain) NSString *account;
@property (nonatomic, retain) NSString *key;
@property (nonatomic, retain) NSString *value;

@end

@interface DirectoryV2 : SeafCacheObjV2

@end

@interface ModifiedFileV2 : SeafCacheObjV2

@end

@interface UploadedPhotoV2 : SeafCacheObjV2

@end



@interface Directory : NSManagedObject

@property (nonatomic, retain) NSString *repoid;
@property (nonatomic, retain) NSString *oid;
@property (nonatomic, retain) NSString *path;
@property (nonatomic, retain) NSString *content;

@end


@interface DownloadedFile : NSManagedObject

@property (nonatomic, retain) NSString *repoid;
@property (nonatomic, retain) NSString *path;
@property (nonatomic, retain) NSString *oid;
@property (nonatomic, retain) NSString *mpath;

@end


@interface SeafCacheObj : NSManagedObject

@property (nonatomic, retain) NSString *url;
@property (nonatomic, retain) NSString *username;
@property (nonatomic, retain) NSString *key;
@property (nonatomic, retain) NSString *content;
@property (nonatomic, retain) NSDate *timestamp;

@end

@interface UploadedPhotos : NSManagedObject
@property (nonatomic, retain) NSString *username;
@property (nonatomic, retain) NSString *server;
@property (nonatomic, retain) NSString *url;
@end
