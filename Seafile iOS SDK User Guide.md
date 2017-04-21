Seafile iOS SDK User Guide


***The code is still under refactoring, anyone who want to use seafile ios sdk should only use the apis listed below.***

### How to use

Seafile is available through CocoaPods. To install it, simply add the following line to your Podfile:

	pod 'Seafile', :git => 'https://github.com/haiwen/seafile-iOS.git', :branch => 'master'

### Api
1. Account auth

	* 	Create a new SeafConnection object with server url, username and password.
		
		SeafConnection *connection = [[SeafConnection alloc] initWithUrl:url cacheProvider:nil];
		
	*  Login

		[connection loginWithUsername:username password:password];
		
	Or two step verification
	
		[connection loginWithUsername:username password:password otp:otp];
	
	You can get notified with SeafConnection.loginDelegate (SeafLoginDelegate). 
	
		@protocol SeafLoginDelegate <NSObject>
		- (void)loginSuccess:(SeafConnection *_Nonnull)connection;
		- (void)loginFailed:(SeafConnection *_Nonnull)connection response:(NSURLResponse *_Nonnull)response error:(NSError *_Nullable)error;
		- (BOOL)authorizeInvalidCert:(NSURLProtectionSpace *_Nonnull)protectionSpace;
		- (NSData *_Nullable)getClientCertPersistentRef:(NSURLCredential *_Nullable __autoreleasing *_Nullable)credential; // return the persistentRef
		@end

2. Data modal

	In Seafile, the main data modals are library, folder, file. We use the following data structures for these modals.
	
	- SeafRepos:	The root, a collection of all libraries.
	- SeafRepo: Library, contains a collection of SeafFiles and SeafDirs
	- SeafDir: A folder in a library.
	- SeafFile: A file in a library.
	- SeafUploadFile: A local file to upload.
	
	SeafRepos,  SeafRepo, SeafDir, SeafFile have a common super class SeafBase. The main api for SeafBase is listed below

		@property (copy) NSString *name; // name
		@property (readonly, copy) NSString *path; // path in the library
		@property (readonly, copy) NSString *repoId; // library id
		@property (readonly, copy) NSString *mime; //mime type
		
		@property (copy) NSString *ooid; // cached object id
		@property (copy) NSString *oid;  // current object id
		
		@property enum SEAFBASE_STATE state; // the state of local object
		
		@property (weak) id <SeafDentryDelegate> delegate; // the delegate
		
		@property (readonly, copy) NSString *shareLink; // shared link
		
		- (BOOL)hasCache;  // has local cache
		- (BOOL)loadCache; // load local cache
		- (void)clearCache;  // clear local cache
		
		// load the content of this entry, force means force load from server. Otherwise will try to load local cache first, if cache miss, load from remote server.
		- (void)loadContent:(BOOL)force;
		- (UIImage *)icon; // icon for this entry
		
		// If local decryption is enabled, check library password locally, otherwise set library password on remote server
		- (void)checkOrSetRepoPassword:(NSString *)password delegate:(id<SeafRepoPasswordDelegate>)del;
		- (void)checkOrSetRepoPassword:(NSString *)password block:(repo_password_set_block_t)block;
		
		- (void)generateShareLink:(id<SeafShareDelegate>)dg; // generate shared link

	
3. List all libraries

		[conn.rootFolder loadContent:NO];
	The result of this operation will be notified by conn.rootFolder.delegate.
	conn.rootFolder.items are all the libraries under the current account.

4. Get folder file list:(SeafDir *dir)
	
		[dir loadContent:NO];
	The result of this operation will be notified by dir.delegate.
	dir.items are all the folders and files under the current account. dir.allItems contains the SeafUploadFiles that will be uploaded to this folder.

5. Download file: (SeafFile * file)
		
		[file loadContent:NO];
	The result of this operation will be notified by file.delegate.
	If download succeeds, the downloaded file will be put into local cache, file.cachePath is the path of cached file.

6. Upload file: (SeafUploadFile * ufile)

	First create a SeafUploadFile object, then set the upload destination and upload delegate.

		SeafUploadFile *ufile = [self getUploadfile:path]; 
		ufile.udir = dir;
		// Add to background upload manager
		[SeafDataTaskManager.sharedObject addBackgroundUploadTask:ufile];
		// Or directly upload
		[ufile doUpload];

	You can get the result and progress of upload operation by ufile.delegate
		
		@protocol SeafUploadDelegate <NSObject>
		- (void)uploadProgress:(SeafUploadFile *)file progress:(int)percent;
		- (void)uploadComplete:(BOOL)success file:(SeafUploadFile *)file oid:(NSString *)oid;
		@end
			
	Or by ufile.progressBlock and ufile.completionBlock
	
		typedef void (^SeafUploadProgressBlock)(SeafUploadFile *file, int progress);
		typedef void (^SeafUploadCompletionBlock)(BOOL success, SeafUploadFile *file, NSString *oid);

	
7. Starred files: (SeafFile *file)

	You can get all the starred files using the SeafConnection:
	
		- (void)getStarredFiles:(void (^ _Nonnull)(NSHTTPURLResponse *  _Nullable response, id _Nullable JSON))success
               	failure:(void (^ _Nonnull)(NSHTTPURLResponse * _Nullable response, NSError * _Nullable error))failure;
    Or get the cached starred files:
    
    	- (id _Nullable)getCachedStarredFiles;
                
    And you can check if a file is starred by:
    	
    	- (BOOL)isStarred:(NSString *_Nonnull)repo path:(NSString *_Nonnull)path;

	Star a file or unstar a file
	
		- (BOOL)setStarred:(BOOL)starred repo:(NSString * _Nonnull)repo path:(NSString * _Nonnull)path;

8. File/folder operation: delete, rename, copy, move files/folders, create new file/folder

	In a parent folder(SeafDir *dir), you can delete, rename, copy, move, create new the files/folders

		- (void)mkdir:(NSString *)newDirName;
		- (void)mkdir:(NSString *)newDirName success:(void (^)(SeafDir *dir))success failure:(void (^)(SeafDir *dir))failure;
		- (void)createFile:(NSString *)newFileName;
		- (void)delEntries:(NSArray *)entries;
		- (void)copyEntries:(NSArray *)entries dstDir:(SeafDir *)dst_dir;
		- (void)moveEntries:(NSArray *)entries dstDir:(SeafDir *)dst_dir;
		- (void)renameFile:(SeafFile *)sfile newName:(NSString *)newName;

delEntries, copyEntries and moveEntries can operate multi files/folders
