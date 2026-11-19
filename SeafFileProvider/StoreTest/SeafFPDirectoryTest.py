"""Run production directory loading/parsing against isolated model and transport doubles."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
src = (root / 'Pod/Classes/SeafDir.m').read_text()
def between(a,b):
    return src[src.index(a):src.index(b,src.index(a))]
header=r'''
#import <Foundation/Foundation.h>
#define Warning(...) do {} while(0)
#define Debug(...) do {} while(0)
#define SEAF_DENTRY_UPTODATE 1
#define SEAF_DENTRY_INIT 0
#define ENTITY_DIRECTORY @"dir"
static id gJSON;
@class SeafConnection, SeafRepo, SeafUploadFile;
@interface NSObject (NumberFallback)
- (NSInteger)integerValue:(NSInteger)fallback;
@end
@implementation NSObject (NumberFallback)
- (NSInteger)integerValue:(NSInteger)fallback { return [self respondsToSelector:@selector(integerValue)]?[(id)self integerValue]:fallback; }
@end
@interface SeafBase : NSObject
@property NSString *name,*path,*oid,*repoId,*fullPath;
@property SeafConnection *connection;
@end
@implementation SeafBase @end
@interface SeafUploadFile : NSObject
@property NSString *editedFileOid,*lpath;
@property id delegate;
@end
@implementation SeafUploadFile @end
@interface SeafFile : SeafBase
@property NSString *thumbnailURLStr;
@property SeafUploadFile *ufile;
- (instancetype)initWithConnection:(id)c oid:(id)o repoId:(id)r name:(id)n path:(id)p mtime:(long long)t size:(long long)s;
- (void)setMpath:(id)p;
@end
@implementation SeafFile
- (instancetype)initWithConnection:(id)c oid:(id)o repoId:(id)r name:(id)n path:(id)p mtime:(long long)t size:(long long)s { if((self=[super init])){self.connection=c;self.oid=o;self.repoId=r;self.name=n;self.path=p;} return self; }
- (void)setMpath:(id)p {}
@end
@interface SeafRepo : SeafBase @end
@implementation SeafRepo @end
@interface SeafFileStatus : NSObject
@property NSString *dirId;
@end
@implementation SeafFileStatus @end
@interface SeafAccountTaskQueue : NSObject
- (NSArray *)getNeedUploadTasks;
@end
@implementation SeafAccountTaskQueue
- (NSArray *)getNeedUploadTasks { return @[]; }
@end
@interface SeafDataTaskManager : NSObject
+ (instancetype)sharedObject;
- (SeafAccountTaskQueue *)accountQueueForConnection:(id)c;
@end
@implementation SeafDataTaskManager
+ (instancetype)sharedObject { return [self new]; }
- (SeafAccountTaskQueue *)accountQueueForConnection:(id)c {return [SeafAccountTaskQueue new];}
@end
@interface Utils : NSObject
+ (BOOL)isMainApp;
@end
@implementation Utils
+ (BOOL)isMainApp { return NO; }
@end
@interface SeafRealmManager : NSObject
+ (instancetype)shared;
- (void)updateFileStatuses:(id)s;
@end
@implementation SeafRealmManager
+ (instancetype)shared {return [self new];}
- (void)updateFileStatuses:(id)s {}
@end
@interface SeafConnection : NSObject
- (SeafRepo *)getRepo:(id)r;
- (void)removeKey:(id)k entityName:(id)e;
- (void)sendRequest:(id)url success:(void (^)(NSURLRequest*, NSHTTPURLResponse*,id))success failure:(void (^)(NSURLRequest*,NSHTTPURLResponse*,id,NSError*))failure;
@end
@implementation SeafConnection
- (SeafRepo *)getRepo:(id)r {return nil;}
- (void)removeKey:(id)k entityName:(id)e {}
- (void)sendRequest:(id)url success:(void (^)(NSURLRequest*, NSHTTPURLResponse*,id))success failure:(void (^)(NSURLRequest*,NSHTTPURLResponse*,id,NSError*))failure {success(nil,[[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://test/"] statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil],gJSON);}
@end
@protocol DirDelegate
- (void)download:(id)dir complete:(BOOL)complete;
- (void)download:(id)dir failed:(NSError*)error;
@end
@interface SeafDir : SeafBase { id _uploadItems; id _allItems; }
@property NSString *ooid,*perm,*cacheKey,*url;
@property NSArray *items;
@property NSInteger state;
@property id<DirDelegate> delegate;
- (instancetype)initWithConnection:(id)c oid:(id)o repoId:(id)r perm:(id)perm name:(id)n path:(id)p mtime:(long long)t;
- (void)buildFileIndexFromItems:(NSArray*)items;
- (void)loadedItems:(NSArray*)items;
- (SeafFileStatus *)parseFileStatus:(id)json;
- (BOOL)savetoCache:(id)json cacheOid:(id)o perm:(id)p;
- (long long)fp_indexStartSeq;
- (void)fp_indexListingForResponse:(id)json startSeq:(long long)s;
- (void)loadContentSuccess:(void (^)(SeafDir*))success failure:(void (^)(SeafDir*,NSError*))failure requireListing:(BOOL)requireListing;
@end
static BOOL SeafFPResponseHasListing(id JSON);
@implementation SeafDir
- (instancetype)initWithConnection:(id)c oid:(id)o repoId:(id)r perm:(id)perm name:(id)n path:(id)p mtime:(long long)t { if((self=[super init])){self.connection=c;self.oid=o;self.repoId=r;self.name=n;self.path=p;} return self; }
- (void)buildFileIndexFromItems:(NSArray*)items {}
- (void)loadedItems:(NSArray*)items {self.items=items;}
- (SeafFileStatus *)parseFileStatus:(id)json {return nil;}
- (BOOL)savetoCache:(id)json cacheOid:(id)o perm:(id)p {return YES;}
- (long long)fp_indexStartSeq {return -1;}
- (void)fp_indexListingForResponse:(id)json startSeq:(long long)s {}
'''
code=header+between('- (BOOL)handleData:(NSString *)oid data:', '- (SeafFileStatus *)parseFileStatus:')+between('- (void)handleResponse:', '- (NSString *)url')+between('- (void)loadContentSuccess:(void (^)(SeafDir *dir)) success', '#pragma mark - Files app index')+between('static BOOL SeafFPResponseHasListing(id JSON)\n{', '- (long long)fp_indexStartSeq')+between('- (void)clearCache\n{', '- (BOOL)savetoCache:')+'\n@end\n'+r'''
int main(void) { @autoreleasepool {
    NSDictionary *listing=@{@"dir_id":@"d1",@"dirent_list":@[@{@"type":@"file",@"name":@"A",@"id":@"x",@"mtime":@1,@"size":@5}]};
    int assertions=0;
    for(int poison=0;poison<2;poison++) {
        SeafDir *d=[SeafDir new];d.connection=[SeafConnection new];d.path=@"/";d.repoId=@"r";
        if(poison) {
            [d handleResponse:nil json:@{@"dir_id":@"d1"}];
            if(d.ooid || d.items) return 1; assertions++;
        }
        gJSON=listing;
        __block BOOL success=NO,failed=NO;
        [d loadContentSuccess:^(SeafDir *r){success=YES;} failure:^(SeafDir *r,NSError *e){failed=YES;} requireListing:YES];
        if(!success || failed || d.items.count!=1) return 1; assertions++;
        // Dropping loaded items cannot make the same directory hash skip parsing.
        [d clearCache]; success=NO;
        [d loadContentSuccess:^(SeafDir *r){success=YES;} failure:^(SeafDir *r,NSError *e){failed=YES;} requireListing:YES];
        if(!success || failed || d.items.count!=1) return 1; assertions++;
        // An unchanged response can confirm already-loaded items.
        gJSON=@"uptodate";success=NO;
        [d loadContentSuccess:^(SeafDir *r){success=YES;} failure:^(SeafDir *r,NSError *e){failed=YES;} requireListing:YES];
        if(!success || failed || d.items.count!=1) return 1; assertions++;
    }
    NSArray *bad=@[@"invalid",@{@"dir_id":@"bad"},@{@"dir_id":@42,@"dirent_list":@[]},
        @{@"dir_id":@"bad",@"dirent_list":@[@42]},@{@"dirent_list":@[@{@"type":@"unknown",@"name":@"A"}]},
        @{@"dirent_list":@[@{@"type":@"file",@"name":@"A/B"}]},@"uptodate"];
    for(id response in bad) for(int strict=0;strict<2;strict++) {
        SeafDir *d=[SeafDir new];d.connection=[SeafConnection new];d.path=@"/";d.repoId=@"r";gJSON=response;
        __block BOOL success=NO,failed=NO;
        [d loadContentSuccess:^(SeafDir *r){success=YES;} failure:^(SeafDir *r,NSError *e){failed=YES;} requireListing:strict];
        if(success || !failed || d.items || d.ooid) return 1; assertions++;
    }
    NSLog(@"RESULT: directory response regressions %d passed, 0 failed",assertions);
    return 0;
} }
'''
with tempfile.TemporaryDirectory(prefix='seaf-fp-directory-regression-') as workspace:
    out = Path(workspace)
    source = out / 'DirectoryTests.m'
    binary = out / 'directory-tests'
    source.write_text(code)
    result = subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', str(source), '-o', str(binary)], capture_output=True, text=True)
    if result.returncode:
        print(result.stdout + result.stderr)
        raise SystemExit(result.returncode)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
