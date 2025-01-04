//
//  SeafFileStatus.h
//  Seafile
//
//  Created by henry on 2024/12/31.
//

#import "RLMObject.h"
#import <Realm/Realm.h>

@interface SeafFileStatus : RLMObject

@property (nonatomic, strong) NSString * _Nonnull uniquePath;          // Full unique file path (host + accountEmail + filePath + fileName)
@property (nonatomic, strong) NSString * _Nullable serverOID;           // Unique identifier from the server
@property (nonatomic, assign) float serverMTime;             // Modification time on the server
@property (nonatomic, assign) float localMTime;              // Modification time locally
@property (nonatomic, strong) NSString * _Nullable localFilePath;       // Local file cache path
@property (nonatomic, assign) float fileSize;                // File size in bytes
@property (nonatomic, assign) BOOL isStarred;                // Indicates whether the file is starred
@property (nonatomic, strong) NSString * _Nullable accountIdentifier;          // Account identifier (host + accountEmail)

@property (nonatomic, strong) NSString * _Nullable dirPath;          //file path Example: '/dirName/1/2'
@property (nonatomic, strong) NSString * _Nullable fileName;          //Example: 'IMG_20240115_155409_4563.PNG'
@property (nonatomic, strong) NSString * _Nullable dirId;             // dir oid. Example: 'e6826a3d84bdb05d573d8778e3c517818f6aa32b'

@end
