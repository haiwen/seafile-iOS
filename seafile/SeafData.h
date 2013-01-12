//
//  SeafData.h
//  seafile
//
//  Created by Wei Wang on 7/25/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface SeafServer : NSManagedObject

@property (nonatomic, retain) NSString *url;
@property (nonatomic, retain) NSString *username;
@property (nonatomic, retain) NSString *content;

@end


@interface StarredFiles : NSManagedObject

@property (nonatomic, retain) NSString *url;
@property (nonatomic, retain) NSString *username;
@property (nonatomic, retain) NSString *content;

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

@end
