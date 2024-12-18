//
//  SeafConnection.h
//  seafile
//
//  Created by Wang Wei on 10/11/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFNetworking.h"
#import "SeafCacheProvider.h"
#import "SeafBase.h"
#import "SeafPhotoBackupTool.h"
#import "ExtentedString.h"
@class SeafFile;

#define HTTP_ERR_UNAUTHORIZED                    401
#define HTTP_ERR_LOGIN_INCORRECT_PASSWORD        400
#define HTTP_ERR_REPO_PASSWORD_REQUIRED          440
#define HTTP_ERR_OPERATION_FAILED                520
#define HTTP_ERR_REPO_UPLOAD_PASSWORD_EXPIRED    500
#define HTTP_ERR_REPO_DOWNLOAD_PASSWORD_EXPIRED  400

#define DEFAULT_TIMEOUT 120
#define LARGE_FILE_SIZE 10*1024*1024

#define REPO_LAST_UPDATE_PASSWORD_TIME @"repoLastPasswordUpdateTsMap"

enum MSG_TYPE{
    MSG_NONE = 0,
    MSG_GROUP,
    MSG_USER,
    MSG_REPLY,
};
/**
 * @class SeafConnection
 * @discussion This class manages network connections to the Seafile server, handling user authentication, data retrieval, and synchronization tasks.
 */
@class SeafConnection;
@class SeafRepos;
@class SeafRepo;
@class SeafUploadFile;
@class SeafDir;

typedef void (^CompletionBlock)(BOOL success, NSError * _Nullable error);

BOOL SeafServerTrustIsValid(SecTrustRef _Nonnull serverTrust);

@protocol SeafLoginDelegate <NSObject>
/**
 * Notifies the delegate that login was successful.
 * @param connection The `SeafConnection` instance that initiated the login.
 */
- (void)loginSuccess:(SeafConnection *_Nonnull)connection;

/**
 * Notifies the delegate that login failed.
 * @param connection The `SeafConnection` instance that initiated the login.
 * @param response The `NSHTTPURLResponse` associated with the login failure.
 * @param error The error describing what went wrong during the login process.
 */
- (void)loginFailed:(SeafConnection *_Nonnull)connection response:(NSHTTPURLResponse *_Nonnull)response error:(NSError *_Nullable)error;

/**
 * Asks the delegate to authorize an invalid or self-signed certificate.
 * @param protectionSpace The `NSURLProtectionSpace` that provides additional context about the authentication request.
 * @return A Boolean value indicating whether the certificate should be authorized.
 */
- (BOOL)authorizeInvalidCert:(NSURLProtectionSpace *_Nonnull)protectionSpace;

/**
 * Requests the persistent reference for a client certificate used for authentication.
 * @return The persistent reference data for the client certificate, if available.
 */
- (NSData *_Nullable)getClientCertPersistentRef:(NSURLCredential *_Nullable __autoreleasing *_Nullable)credential; // return the persistentRef

@end

@protocol SeafConnectionDelegate <NSObject>
/**
 * Notifies the delegate that a login is required.
 * @param connection The `SeafConnection` instance that requires the user to log in.
 */
- (void)loginRequired:(SeafConnection *_Nonnull)connection;

/**
 * Notifies the delegate that the connection has exceeded its quota.
 * @param connection The `SeafConnection` instance that has run out of quota.
 */
- (void)outOfQuota:(SeafConnection *_Nonnull)connection;

@end


@interface SeafConnection: NSObject


@property (readonly, retain) NSMutableDictionary * _Nonnull info;///< General information about the connection.
@property (readwrite, nonatomic, copy) NSString * _Nullable address;///< The server address.
@property (weak) id <SeafLoginDelegate> _Nullable loginDelegate;///< Delegate for handling login events.
@property (weak) id <SeafConnectionDelegate> _Nullable delegate;///< Delegate for connection-related events.
@property (strong) SeafRepos *_Nullable rootFolder;///< Root folder object representing the top directory in the server.
@property (readonly) AFHTTPSessionManager * _Nonnull sessionMgr; ///< Session manager for regular HTTP requests.
@property (readonly) AFHTTPSessionManager * _Nonnull loginMgr;///< Session manager for login requests.
@property (nonatomic, readonly) NSString * _Nonnull accountIdentifier;///< Unique identifier for the user's account.
@property (readonly) NSString * _Nullable username;///< Username of the Seafile account.
@property (readonly) NSString * _Nullable password;///< Password of the Seafile account.
@property (readonly) NSString * _Nullable host;///< Host URL of the Seafile server.
@property (readonly) BOOL isShibboleth;///< Indicates whether Shibboleth authentication is used.
@property (readonly) long long quota;///< Total quota available on the server for the user.
@property (readonly) long long usage;///< Current data usage by the user.
@property (readonly, strong) NSString* _Nullable token;///< Authentication token.
@property (readonly) BOOL authorized;///< Indicates whether the user is currently authorized.
@property (readonly) BOOL isSearchEnabled;///< Indicates whether search functionality is enabled on the server.
@property (readonly) BOOL isActivityEnabled;///< Indicates whether activity tracking is enabled on the server.
@property (readonly) BOOL isNewActivitiesApiSupported;///< Indicates whether the new activities API is supported.
@property (readonly) NSData* _Nullable clientIdentityKey;///< Client identity key for secure communications.

@property (readwrite, nonatomic, getter=isWifiOnly) BOOL wifiOnly;///< Indicates whether syncing should occur over WiFi only.
@property (readwrite, nonatomic, getter=isAutoSync) BOOL autoSync; ///< Indicates whether automatic syncing is enabled.
@property (readwrite, nonatomic, getter=isVideoSync) BOOL videoSync;///< Indicates whether video syncing is enabled.
@property (readwrite, nonatomic, getter=isBackgroundSync) BOOL backgroundSync;///< Indicates whether background syncing is enabled.
@property (readwrite, nonatomic, getter=isFirstTimeSync) BOOL firstTimeSync;///< Indicates whether this is the first time syncing.
@property (assign, nonatomic, getter=isUploadHeicEnabled) BOOL uploadHeicEnabled;///< Indicates whether HEIC photo upload is enabled.

@property (readwrite, nonatomic) NSString * _Nullable autoSyncRepo;///< Repository ID for automatic synchronization.

@property (readwrite, nonatomic) BOOL autoClearRepoPasswd; ///< Indicates whether to automatically clear repository passwords.
@property (readwrite, nonatomic) BOOL localDecryptionEnabled;///< Indicates whether local decryption is enabled.
@property (readwrite, nonatomic) BOOL touchIdEnabled;///< Indicates whether Touch ID is enabled for authentication.
@property (readonly) NSURLCredential *_Nullable clientCred;///< Client credentials for authentication.

@property (assign,nonatomic) BOOL inAutoSync;///< Indicates whether the connection is currently in auto-sync mode.

@property (readonly) NSString *_Nullable avatar;///< Path to the user's avatar.

@property (nonatomic, strong) SeafPhotoBackupTool * _Nullable photoBackup;///< Tool for backing up photos.

@property (readonly) NSString * _Nullable localUploadDir;

/**
 * Initializes a new connection with a specified URL and an optional cache provider.
 * @param url The URL to the Seafile server.
 * @param cacheProvider An object conforming to the SeafCacheProvider protocol to handle caching.
 * @return An instance of SeafConnection.
 */
- (id _Nonnull)initWithUrl:(NSString *_Nonnull)url cacheProvider:(id<SeafCacheProvider> _Nullable )cacheProvider;

/**
 * Initializes a new connection with a URL, cache provider, and username.
 * @param url The URL to the Seafile server.
 * @param cacheProvider An object conforming to the SeafCacheProvider protocol to handle caching.
 * @param username The username associated with this connection.
 * @return An instance of SeafConnection.
 */
- (id _Nonnull)initWithUrl:(NSString * _Nonnull)url cacheProvider:(id<SeafCacheProvider> _Nullable )cacheProvider username:(NSString * _Nonnull)username ;


- (void)loadRepos:(id<SeafDentryDelegate> _Nullable)degt;

- (BOOL)localDecrypt;
- (BOOL)isEncrypted:(NSString * _Nonnull)repoId;
- (BOOL)shouldLocalDecrypt:(NSString * _Nonnull)repoId;

- (void)resetUploadedPhotos;
- (void)clearAccount;
- (void)logout;

- (NSUInteger)autoSyncedNum;
- (NSString * _Nonnull)uniqueUploadDir;

/**
 Constructs a request with a specified method and form data.
 @param url The URL to which the request should be sent.
 @param method The HTTP method to use (e.g., “GET”, “POST”).
 @param form An optional string of form data to include in the request.
 @return A configured NSMutableURLRequest.
 */
- (NSURLRequest * _Nonnull)buildRequest:(NSString * _Nonnull)url method:(NSString * _Nonnull)method form:(NSString *_Nullable)form;

/**
 * Sends a HTTP request to the server.
 * @param url The URL where the request is sent.
 * @param success A block that is called if the request is successful, returning the request, response, and JSON data.
 * @param failure A block that is called if the request fails, returning the request, response, optional JSON data, and an error.
 */
- (NSURLSessionDataTask *_Nullable)sendRequest:(NSString * _Nonnull)url
            success:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id _Nonnull JSON))success
            failure:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id _Nullable JSON, NSError * _Nullable error))failure;

/**
 Sends a DELETE request to a specified URL, handling success and failure scenarios.
 @param url The URL from which the resource should be deleted.
 @param success A block to execute if the request succeeds.
 @param failure A block to execute if the request fails.
 */
- (void)sendDelete:(NSString * _Nonnull)url
           success:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id _Nonnull JSON))success
           failure:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id _Nullable JSON, NSError * _Nullable error))failure;

/**
 Sends a PUT request with form data to a specified URL, handling success and failure scenarios.
 @param url The URL to which the PUT request should be sent.
 @param form A string of form data to include in the request.
 @param success A block to execute if the request succeeds.
 @param failure A block to execute if the request fails.
 */
- (void)sendPut:(NSString * _Nonnull)url form:(NSString * _Nullable)form
        success:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id _Nonnull JSON))success
        failure:(void (^ _Nullable)(NSURLRequest *_Nonnull request, NSHTTPURLResponse * _Nullable response, id _Nullable JSON, NSError * _Nullable error))failure;

/**
 Sends a POST request with form data to a specified URL, handling success and failure scenarios.
 @param url The URL to which the POST request should be sent.
 @param form A string of form data to include in the request.
 @param success A block to execute if the request succeeds.
 @param failure A block to execute if the request fails.
 */
- (NSURLSessionDataTask *_Nullable)sendPost:(NSString * _Nonnull)url form:(NSString * _Nullable)form
         success:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id _Nonnull JSON))success
         failure:(void (^_Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id _Nullable JSON, NSError * _Nullable error))failure;

/**
 Sends an OPTIONS request to a specified URL, handling success and failure scenarios.
 @param url The URL to which the OPTIONS request should be sent.
 @param success A block to execute if the request succeeds.
 @param failure A block to execute if the request fails.
 */
- (void)sendOptions:(NSString * _Nonnull)url
            success:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id _Nonnull JSON))success
            failure:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id _Nullable JSON, NSError * _Nullable error))failure;

/**
 * Logs in with the specified username and password.
 * @param username The username for login.
 * @param password The password for login.
 */
- (void)loginWithUsername:(NSString * _Nonnull)username password:(NSString * _Nonnull)password;

/**
 * Logs in with username, password, and optionally a one-time password for two-factor authentication, and an option to remember the device.
 * @param username The username for login.
 * @param password The password for login.
 * @param otp Optional one-time password for two-factor authentication.
 * @param remember Whether to remember the device, reducing the need for future two-factor authentication.
 */
- (void)loginWithUsername:(NSString * _Nonnull)username password:(NSString * _Nonnull)password otp:(NSString * _Nullable)otp rememberDevice:(BOOL)remember;

/**
 * Sets the authentication token for the user session, useful for subsequent requests requiring authentication.
 * @param token The authentication token to be set.
 * @param username The username associated with this token.
 * @param isshib Indicates whether Shibboleth authentication was used.
 * @param s2faToken Token used for second-factor authentication, if any.
 */
-(void)setToken:(NSString * _Nonnull)token forUser:(NSString * _Nonnull)username isShib:(BOOL)isshib s2faToken:(NSString*)s2faToken;

/**
 * Fetches detailed account information from the server and triggers the completion handler upon success or failure.
 * @param handler A block that is executed with the result indicating success or failure.
 */
- (void)getAccountInfo:(void (^ _Nullable)(bool result))handler;

/**
 * Initiates a request to fetch starred files from the server.
 * @param success A block that is called with the server response and JSON data if the request succeeds.
 * @param failure A block that is called with the server response and error if the request fails.
 */
- (void)getStarredFiles:(void (^ _Nonnull)(NSHTTPURLResponse *  _Nullable response, id _Nullable JSON))success
                failure:(void (^ _Nonnull)(NSHTTPURLResponse * _Nullable response, NSError * _Nullable error))failure;

/**
 * Retrieves server configuration details such as version and enabled features.
 * @param handler A block that is called with the result indicating whether the retrieval was successful.
 */
- (void)getServerInfo:(void (^ _Nullable)(bool result))handler;

/**
 * Searches for files across repositories that match a given keyword.
 * @param keyword The search term used to find files.
 * @param repoId The identifier of the repository to search within.
 * @param success A block that is called with the request, response, JSON data, and an array of search results.
 * @param failure A block that is called with the request, response, JSON data, and an error if the search fails.
 */
- (void)search:(NSString *_Nonnull)keyword repo:(NSString * _Nonnull)repoId
       success:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nonnull response, id  _Nonnull JSON, NSMutableArray * _Nonnull results))success
       failure:(void (^ _Nullable)(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, id _Nullable JSON, NSError * _Nullable error))failure;

/**
 * Determines whether a specific repository item (file or folder) is starred.
 * @param repo The repository identifier.
 * @param path The path of the item within the repository.
 * @return A Boolean indicating whether the item is starred.
 */
- (BOOL)isStarred:(NSString *_Nonnull)repo path:(NSString *_Nonnull)path;

/**
 * Marks or unmarks a repository item (file or folder) as starred.
 * @param starred A Boolean indicating whether to star (YES) or unstar (NO) the item.
 * @param repo The repository identifier.
 * @param path The path of the item within the repository.
 * @return A Boolean indicating whether the operation was successful.
 */
- (BOOL)setStarred:(BOOL)starred repo:(NSString * _Nonnull)repo path:(NSString * _Nonnull)path;

/**
 * Retrieves a SeafRepo object representing a repository by its identifier.
 * @param repo The identifier of the repository to retrieve.
 * @return An instance of SeafRepo representing the specified repository, or nil if it cannot be found.
 */
- (SeafRepo * _Nullable)getRepo:(NSString * _Nonnull)repo;

//Deprecated
- (void)registerDevice:(NSData * _Nonnull)deviceToken;

/**
 * Fetches an avatar image for a specific account.
 * @param email The email associated with the account for which to fetch the avatar.
 * @return An image object representing the avatar, or nil if it cannot be fetched.
 */
- (UIImage * _Nullable)avatarForAccount:(NSString * _Nonnull)email;

// Cache
- (void)clearAccountCache;

/**
 Retrieves an object associated with a specified key from a cache.
 @param key The key associated with the object.
 @param entity The entity name under which the object is stored.
 @return The object associated with the key, or nil if it does not exist.
 */
- (NSString * _Nullable)objectForKey:(NSString * _Nonnull)key entityName:(NSString * _Nonnull)entity;

/**
 Sets a value for a specified key in a cache.
 * @param value The value to store.
 * @param key The key under which the value should be stored.
 * @param entity The entity name under which the value should be stored.
 * @return YES if the value was successfully set, otherwise NO.
 */
- (BOOL)setValue:(NSString * _Nonnull)value forKey:(NSString * _Nonnull)key entityName:(NSString * _Nonnull)entity;

/**
 * Removes an object associated with a specified key from a cache.
 * @param key The key associated with the object to remove.
 * @param entity The entity name under which the object is stored.
 */
- (void)removeKey:(NSString * _Nonnull)key entityName:(NSString *_Nonnull)entity;

/**
 * Retrieves the total number of cached objects for a specified entity.
 * @param entity The entity name for which to count cached objects.
 * @return The total number of cached objects.
 */
- (long)totalCachedNumForEntity:(NSString * _Nonnull)entity;

/**
 * Clears the cache for a specified entity.
 * @param entity The entity name for which to clear the cache.
 */
- (void)clearCache:(NSString * _Nonnull)entity;

/**
 * Retrieves JSON data from a cache, decoding it into an object.
 * @param key The key associated with the JSON data.
 * @param entity The entity name under which the JSON data is stored.
 * @return The decoded JSON object, or nil if the data could not be decoded or does not exist.
 */
- (id _Nullable)getCachedJson:(NSString * _Nonnull)key entityName:(NSString * _Nonnull)entity;

/**
 * Retrieves the cached data for starred files, updating the internal list of starred files if necessary.
 * @return The decoded JSON object containing starred file information, or nil if the data could not be decoded or does not exist.
 */
- (id _Nullable)getCachedStarredFiles;

/**
 * Retrieves an attribute from the connection's settings dictionary.
 * @param aKey The key associated with the attribute.
 * @return The object associated with the key, or nil if no object exists.
 */
- (id _Nullable)getAttribute:(NSString * _Nonnull)aKey;

/**
 * Sets a given attribute in the connection's settings dictionary.
 * @param anObject The object to store in the settings.
 * @param aKey The key under which to store the object.
 */
- (void)setAttribute:(id _Nullable )anObject forKey:(NSString * _Nonnull)aKey;

/**
Checks the auto synchronization settings and updates the connection’s synchronization actions accordingly.
*/
- (void)checkAutoSync;

/**
 * Returns the number of photos currently being synced.
 * @return The number of photos in syncing process.
 */
- (NSUInteger)photosInSyncing;

/**
 * Checks if the photo library is currently being checked for syncing.
 */
- (BOOL)isCheckingPhotoLibrary;


- (void)checkSyncDst:(SeafDir *_Nonnull)dir;

/**
 * Handles changes in the photo library and initiates a photo sync if auto sync is enabled.
 * @param note The notification object containing the change details.
 */
- (void)photosDidChange:(NSNotification *_Nullable)note;

/**
 * Saves a repository password and its last update timestamp into the account information.
 * @param repoId The identifier for the repository whose password is to be saved.
 * @param password The new password for the repository.
 */
- (void)saveRepo:(NSString * _Nonnull)repoId password:(NSString * _Nullable)password;

/**
 * Saves encryption information for a specific repository into the account settings.
 * This method updates the encryption info associated with a specific repository ID and then saves the updated account information persistently.
 * @param repoId The repository identifier to which the encryption info belongs.
 * @param encInfo A dictionary containing the encryption details for the repository.
 */
- (void)saveRepo:(NSString *_Nonnull)repoId encInfo:(NSDictionary *_Nonnull)encInfo;

/**
 * Retrieves the stored password for a specific repository.
 * @param repoId The repository identifier for which the password is being requested.
 * @return The password for the repository if found, otherwise returns nil if the password does not exist or the dictionary is not available.
 */
- (NSString * _Nullable)getRepoPassword:(NSString * _Nonnull)repoId;

/**
 * Retrieves the encryption information for a specific repository.
 * @param repoId The repository identifier for which the encryption information is being requested.
 * @return The dictionary containing encryption details for the repository if found, otherwise returns nil if no information exists or the dictionary is not available.
 */
- (NSDictionary *_Nullable)getRepoEncInfo:(NSString * _Nonnull)repoId;

/**
 * Initiates the download of a directory and all its contents recursively.
 * @param dir The directory object that needs to be downloaded.
 */
- (void)downloadDir:(SeafDir * _Nonnull)dir;

/**
 * Refreshes the stored passwords for all repositories.
 */
- (void)refreshRepoPasswords;

/**
 * Clears all stored repository passwords and related information.
 */
- (void)clearRepoPasswords;

/**
 * Retrieves the last password refresh time for a specified repository.
 * @param repoId The identifier of the repository for which to retrieve the last password refresh time.
 * @return NSTimeInterval representing the last refresh time of the repository's password.
 *         Returns 0 if there is no timestamp available, indicating that the password has never been updated.
 */
- (NSTimeInterval)getRepoLastRefreshPasswordTime:(NSString *_Nullable)repoId;

// fileProvider tagData
/**
 * Saves file provider tag data for a specific item to local and iCloud storage.
 * @param tagData The NSData object containing tag data to be stored.
 * @param itemId The unique identifier for the item whose tag data is being updated or removed.
 */
- (void)saveFileProviderTagData:(NSData * _Nullable)tagData withItemIdentifier:(NSString * _Nullable)itemId;

/**
 * Loads the file provider tag data associated with a specific item identifier from local storage.
 * @param itemId The unique identifier for the item whose tag data is to be retrieved.
 * @return An NSData object containing the tag data for the item, or nil if no data is found.
 */
- (NSData * _Nullable)loadFileProviderTagDataWithItemIdentifier:(NSString * _Nullable)itemId;

/**
 * Returns a shared instance of `AFHTTPRequestSerializer` which implements `AFURLRequestSerialization` protocol.
 * @return A singleton `AFHTTPRequestSerializer` instance that can be used to serialize `NSURLRequest` objects.
 */
+ (AFHTTPRequestSerializer <AFURLRequestSerialization> * _Nonnull)requestSerializer;

/**
 *
    Connetion clear upload cache
 */
- (void)clearUploadCache;

/**
 *
    Build starred thumbnail image url string
 */
- (NSString *_Nullable)buildThumbnailImageUrlFromSFile:(SeafFile *_Nullable)sFile;

@end
