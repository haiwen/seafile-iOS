//
//  SeafRepos.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import "SeafDir.h"

#define SHARE_REPO @"shared"
#define GROUP_REPO @"group"
#define MINE_REPO @"mine"
#define PUBLIC_REPO @"public"

#define ORG_REPO @"Organization"

/**
 * A `SeafRepo` object represents a repository in Seafile, a directory that supports version control.
 */
@interface SeafRepo : SeafDir<SeafSortable>
@property (readonly) NSString *repoType;///< Type of the repository (e.g., shared, group, personal).
@property (readonly, copy) NSString *desc;///< Description of the repository.
@property (readonly, copy) NSString *owner; ///< Owner of the repository.
@property (readonly, copy) NSString *ownerNickname;///< Nickname of the repository owner.
@property (readonly, copy) NSString *magic;///< Magic string used for repository encryption.
@property (readonly, copy) NSString *encKey;///< Encryption key for the repository.
@property (readonly) BOOL passwordRequired; ///< Indicates whether a password is required to access the repository.
@property (readonly, nonatomic, assign) BOOL passwordRequiredWithSyncRefresh; ///< Indicates whether a password is required with a sync refresh.
//@property (assign, nonatomic) BOOL encrypted;///< Indicates whether the repository is encrypted.
@property (readonly) int encVersion; ///< Encryption version.
@property (readonly) unsigned long long size;///< Size of the repository.
@property (assign, nonatomic) long long mtime;///< Modification time of the repository.
@property (readonly) NSString *type;///< Type of the repository.
@property (readonly) NSString *groupName;///< Group name associated with the repository, if any.
@property (readonly) NSInteger groupid;///< Group ID associated with the repository, if any.

/**
 * Returns a detailed description of the repository including its last modification time and owner's nickname.
 * @return A formatted string with details about the repository.
 */
- (NSString *)detailText;

/**
 * Indicates whether the repository is a group repository.
 * @return `YES` if it is a group repository, otherwise `NO`.
 */
- (BOOL)isGroupRepo;


// If local decryption is enabled, check library password locally, otherwise set library password on remote server
- (void)checkOrSetRepoPassword:(NSString *)password delegate:(id<SeafRepoPasswordDelegate>)del;
- (void)checkOrSetRepoPassword:(NSString *)password block:(repo_password_set_block_t)block;

//init repo with repoId and name,used to handle 'checkOrSetRepoPassword:' method
- (id)initWithConnection:(SeafConnection *)aConnection andRepoId:(NSString *)aRepoId andRepoName:(NSString *)aName;

@end

/**
 * Manages and groups multiple `SeafRepo` objects.
 */
@interface SeafRepos : SeafDir
@property NSMutableArray *repoGroups;///< Groups of repositories.

/**
 * Initializes a `SeafRepos` instance with the given Seafile connection.
 * @param aConnection The connection to use for interacting with the Seafile server.
 * @return An initialized `SeafRepos` instance.
 */
- (id)initWithConnection:(SeafConnection *)aConnection;

/**
 * Retrieves a specific repository by its identifier.
 * @param repo The repository identifier.
 * @return The `SeafRepo` object if found; otherwise, `nil`.
 */
- (SeafRepo *)getRepo:(NSString *)repo;

/**
 * Creates a new library on the server.
 * @param newLibName The name of the new library.
 * @param passwd The password for the new library, if it is to be encrypted.
 * @param completeBlock The block to execute upon completion, passing the result and any additional repository info.
 */
- (void)createLibrary:(NSString *)newLibName passwd:(NSString*)passwd block:(void(^)(bool success, id repoInfo))completeBlock;

@end
