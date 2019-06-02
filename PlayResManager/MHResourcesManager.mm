//
//  MHResourcesManager.m
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/11/30.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import "MHResourcesManager.h"
#include <CommonCrypto/CommonCrypto.h>
#include <map>
#include <string>
#include <vector>
#include <mutex>
#include <list>
#import "ASIHTTPRequest.h"
#import "MHM3U8Loader.h"
#import "ASIDataDecompressor.h"
#import <IJKMediaFramework/IJKMediaFramework.h>
#import "tmd5.h"
#import "MHAESCrypto.h"
#import "m3u8_parser.h"
#import "loaders/MHPrivateM3U8Loader.h"
#import <dirent.h>
#import <sys/stat.h>
#import "MHResourcesManager_private.h"
#import "MHNewCrypto.h"

#define MEMORY_LIMIT ((long) 1024)


#ifdef DEBUG

std::string log_path;
std::mutex log_mutex;

void log_info(const char *str)  {
    log_mutex.lock();
    if (log_path.empty()) {
        NSString *root = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"logs"];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:root]) {
            [fm createDirectoryAtPath:root
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
        }
        log_path = root.UTF8String;
        log_path += "/log.log";
        NSString *logPath = [NSString stringWithUTF8String:log_path.c_str()];
        if ([fm fileExistsAtPath:logPath]) {
            [fm removeItemAtPath:logPath error:nil];
        }
    }
    FILE *file = fopen(log_path.c_str(), "a+");
    if (file) {
        fwrite(str, strlen(str), 1, file);
        fwrite("\n", 1, 1, file);
        fclose(file);
    }
    log_mutex.unlock();
}

#else

#define log_info(str) ;

#endif

NSString * const MHResourceReadRefreshNotification = @"MHResourceReadRefresh";

using namespace std;

extern NSString *const MHResourceSetStatusChangedNotification = @"MHResourceSetStatusChanged";

@interface MHResourceItem () <ASIHTTPRequestDelegate, NSURLSessionDataDelegate>

@property (nonatomic, weak) MHResourceSet *resource;
@property (nonatomic, assign) NSUInteger index;
@property (atomic, assign) MHResourceItemStatus status;

- (void)checkStatus;
- (void)reset;

- (void)clearMemory;

- (void)startWithComplete:(MHResourceItemOnComplete)onComplete;
- (void)stopWithComplete:(MHResourceItemOnComplete)onComplete;

@end

unsigned long long MH_freeMemory() {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSDictionary *dic = [fm attributesOfFileSystemForPath:cachePath error:nil];
    NSNumber *_free = [dic objectForKey:NSFileSystemFreeSize];
    return _free.unsignedLongLongValue;
}


@interface MHResourceSet () {
    NSMutableDictionary *_keyStore;
}

@property (nonatomic, assign) MHResourceSetStatus status;
@property (nonatomic, readonly) uint8_t rStatus;
@property (nonatomic, readonly) dispatch_queue_t dispatchQueue;

@property (nonatomic, readonly) NSMutableDictionary *cryptoCache;

- (id)initWithPath:(NSString *)path key:(NSString *)key;
- (void)setManager:(MHResourcesManager *)manager;

- (void)onItemRequestStart:(MHResourceItem *)item;
- (void)onItemRequestComplete:(MHResourceItem *)item during:(NSTimeInterval)during;
- (void)onItemRequestFailed:(MHResourceItem *)item;
- (void)onItemDownloaded:(MHResourceItem *)item size:(NSUInteger)size;

- (void)onClock;

- (NSData *)keyStore:(NSString *)url;

- (void)onPlayerItemExit:(MHResourcePlayItem *)item;
- (void)onPause;

@end


@interface MHResourcesManager () {
    NSDictionary<NSString *, NSString *> *_customerHttpHeaders;
}

@property (nonatomic, assign) BOOL playing;

- (void)removeResource:(NSString *)key;

- (void)onResourceSetStarted:(MHResourceSet *)resources;
- (void)onResourceSetStoped:(MHResourceSet *)resources;

- (NSNumber *)maskkeyForKey:(NSString *)key;

@end

@interface MHResourcePlayItem()

@property (nonatomic, weak) MHResourceSet *resource;

- (void)start;

@end

@implementation MHResourcePlayItem {
    NSRange _requestRange;
    NSMutableArray <MHResourceItem *> *_currentDownloadings;
    MHResourceItemOnComplete    _onComplete;
    NSInteger _currentIndex;
    
    MHResourceItem* _currentItem;
    dispatch_semaphore_t _pauseSemaphore;
    id _nextItem;
}

- (id)init {
    self = [super init];
    if (self) {
        _currentIndex = -1;
        _preloadCount = [MHResourcesManager instance].preloadCount;
        _playerNumber = -1;
        _pauseSemaphore = dispatch_semaphore_create(0);
    }
    return self;
}

- (void)start {
    _active = YES;
    self->_requestRange.location = 0;
    self->_requestRange.length = 0;
}

- (int)requirePlay:(NSInteger)index {
    NSLog(@"SEEK: requirePlay %d!", (int)index);
    if (!self.active) {
        return -1;
    }
    while (_isPaused) {
        dispatch_semaphore_wait(_pauseSemaphore, DISPATCH_TIME_FOREVER);
    }
    if (index < self.resource.items.count) {
        _currentIndex = index;
        if (index >= _requestRange.location && index <= _requestRange.location + _requestRange.length) {
            MHResourceItem *item = [self.resource.items objectAtIndex:index];
            if (item.status == MHResourceItemFailed || item.status == MHResourceItemNotStart) {
                _requestRange.length = index - _requestRange.location;
                [self requestForward];
            }
        }else {
            _requestRange.location = index;
            _requestRange.length = 0;
            [self requestForward];
        }
    }
    return 0;
}

- (void)exitPlaying {
    dispatch_sync(self.resource.dispatchQueue, ^{
        [_currentItem stopWithComplete:_onComplete];
        [self.resource onPlayerItemExit:self];
    });
}

- (NSUInteger)cachedTo {
    NSUInteger end = _currentIndex;
    if (_currentIndex < self.resource.items.count) {
        if ([self.resource.items objectAtIndex:_currentIndex].status == MHResourceItemFailed) {
            return 0;
        }
    }
    for (; end < self.resource.items.count; ++end) {
        MHResourceItem *item = [self.resource.items objectAtIndex:end];
        if (item.status != MHResourceItemComplete) {
            return end;
        }
    }
    return self.resource.items.count;
}

- (void)startItem:(MHResourceItem *)item {
    __weak MHResourcePlayItem *that = self;
    [_currentItem stopWithComplete:_onComplete];
    _onComplete = ^(NSError * _Nonnull error) {
        [that requestForward];
    };
    [item startWithComplete:_onComplete];
    _currentItem = item;
}

- (void)requestForward {
    if (!self.active) {
        return;
    }
    while (true) {
        NSInteger off = _requestRange.location + _requestRange.length;
        if (off > _currentIndex + self.preloadCount || off >= self.resource.items.count) {
            break;
        }
        MHResourceItem *item = [self.resource.items objectAtIndex:off];
        _requestRange.length++;
        if (item.status == MHResourceItemComplete) {
            continue;
        }else if (item.status == MHResourceItemNotStart || item.status == MHResourceItemFailed) {
            if (_isPaused) {
                _nextItem = item;
            }else
                [self startItem:item];
            break;
        }else {
            break;
        }
    }
}

- (void)pause {
    _isPaused = YES;
    [self.resource onPause];
}

- (void)resume {
    _isPaused = NO;
    if (_nextItem) {
        [self startItem:_nextItem];
        _nextItem = nil;
    }
    dispatch_semaphore_signal(_pauseSemaphore);
}

@end

@implementation MHResourceItem {
    NSString *_path;
    ASIHTTPRequest *_request;
    vector<char> _buffer;
    NSTimeInterval  _startTime;
    ASIDataDecompressor *_decompressor;
    MHAESCrypto *_crypto;
    MHNewCrypto *_newCrypto;
    NSURLSession *_session;
    
    NSInteger _tryNum;
    
    NSUInteger  _contentLength;
    
    std::mutex _mutex;
    
    list<MHResourceItemOnComplete> _onCompletes;
    std::mutex _onCompleteMutex;
}

- (id)initWithResource:(MHResourceSet *)resource segment:(nonnull IJKHLSSegment *)seg {
    self = [super init];
    if (self) {
        _resource = resource;
        _segment = seg;
        NSString *filename = [seg.url lastPathComponent];
        filename = [[filename componentsSeparatedByString:@":"] firstObject];
        _path = [_resource.path stringByAppendingFormat:@"/%@", filename];
    }
    return self;
}

- (void)checkStatus {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    _status = [fileManager fileExistsAtPath:_path] ? MHResourceItemComplete : MHResourceItemNotStart;
    if (self.status == MHResourceItemComplete) {
        NSDictionary *dic = [fileManager attributesOfItemAtPath:_path error:nil];
        _diskSize = [[dic objectForKey:NSFileSize] unsignedIntegerValue];
    }
}

typedef struct MHRM_mask {
    uint8_t mask[4];
} MHRM_mask;

static MHRM_mask MHRM_getMask(NSUInteger mask_key) {
    MHRM_mask mask;
    mask.mask[0] = (mask_key / 0x1000000 % 0x100) & 0xff;
    mask.mask[1] = (mask_key / 0x10000 % 0x100) & 0xff;
    mask.mask[2] = (mask_key / 0x100 % 0x100) & 0xff;
    mask.mask[3] = (mask_key % 0x100) & 0xff;
    return mask;
}

- (int) __attribute__((annotate(("kiwiobf")))) checkDecrypt:(uint8_t *)buf size:(int)size offset:(size_t)offset {
    // check if response need decrypt
    NSNumber *number = [self.resource.manager maskkeyForKey:self.resource.key];
    if (number) {
        NSUInteger maskkey = [number unsignedIntegerValue];
        MHRM_mask mask = MHRM_getMask(maskkey);
        for (size_t i = 0; i < size; ++i) {
            buf[i] = buf[i] ^ mask.mask[i % 4];
        }
    }
    if (_segment.type != IJKHLSSegmentNone) {
        if (!_crypto) {
            NSData *key = [_resource keyStore:_segment.key];
            if (!key) {
                return 0;
            }
            _crypto = [[MHAESCrypto alloc] initWithKey:(const uint8_t *)key.bytes
                                                    iv:_segment.iv];
        }
        return (int)[_crypto decrypt:buf size:size];
    }else if (_segment.secretKeyIndex >= 0) {
        if (!_newCrypto) {
            _newCrypto = [[MHNewCrypto alloc] initWithKey:_segment.secretKey.UTF8String
                                                    index:_segment.secretKeyIndex];
        }
        if (_newCrypto.isCrypted) return (int)[_newCrypto decrypt:buf size:size offset:offset];
    }
    return size;
}

//static dispatch_semaphore_t MHReader_Semaphore = dispatch_semaphore_create(0);
//// 1 exit 2 reload
//static NSInteger MHReader_Semaphore_Code = 0;

- (int)readData:(uint8_t *)buf size:(int)size offset:(NSUInteger)offset {
    // 20秒超时？
#define TIMEOUT 40
#define CHECK_INTERVAL 0.2
restart:
    
    NSInteger r_count = 0;
    while (r_count++ < (TIMEOUT/CHECK_INTERVAL)) {
        if (self.status == MHResourceItemComplete) {
            FILE *file = fopen(_path.UTF8String, "r");
            if (file) {
                fseek(file, offset, SEEK_SET);
                size_t ret = fread(buf, 1, size, file);
                fclose(file);
                return [self checkDecrypt:buf size:(int)ret offset:(size_t)offset];
            }else {
                @synchronized (self) {
                    if (_buffer.size() >= size + offset){
                        memcpy(buf, _buffer.data() + offset, size);
                        return [self checkDecrypt:buf size:size offset:(size_t)offset];
                    }
                }
            }
            return 0;
        }else if (self.status == MHResourceItemLoading) {
            BOOL retry = NO;
            @synchronized (self) {
                retry = YES;
            }
            if (retry) {
                [NSThread sleepForTimeInterval:CHECK_INTERVAL];
            }
        }else if (self.status == MHResourceItemFailed) {
            NSLog(@"gen:request fail : %@", self.segment.url);
            [NSThread sleepForTimeInterval:0.1];
            return 0;
        }else if (self.status == MHResourceItemNotStart) {
            NSLog(@"gen:request not start : %@", self.segment.url);
            [NSThread sleepForTimeInterval:0.1];
            return -1;
        }
    }
    
    return 0;
}

- (void)refreshReadFailed {
}

- (NSData *)readAllData {
    NSInteger r_count = 0;
    while (r_count++ < (TIMEOUT/CHECK_INTERVAL)) {
        if (self.status == MHResourceItemComplete) {
            NSData *data = [NSData dataWithContentsOfFile:_path];
            uint8_t *buf = (uint8_t*)data.bytes;
            [self checkDecrypt:buf size:(int)data.length offset:0];
            return data;
        }else if (self.status == MHResourceItemLoading) {
            [NSThread sleepForTimeInterval:CHECK_INTERVAL];
        }
    }
    return nil;
}

- (void)dealloc {
    [_request clearDelegatesAndCancel];
    [_session invalidateAndCancel];
}

- (void)start {
    [self startWithComplete:nil];
}

- (void)startWithComplete:(MHResourceItemOnComplete)onComplete {
    @synchronized (self) {
        if (self.status == MHResourceItemNotStart || self.status == MHResourceItemFailed) {
            [self _start];
            
            _tryNum = 0;
            _startTime = [NSDate date].timeIntervalSince1970;
        }
    }
    if (onComplete) {
        switch (self.status) {
            case MHResourceItemLoading:
                _onCompleteMutex.lock();
                _onCompletes.push_back(onComplete);
                _onCompleteMutex.unlock();
                break;
            case MHResourceItemComplete:
                onComplete(nil);
                break;
                
            default:
                break;
        }
    }
}

- (void)_start {
    if (_request) {
        [_request clearDelegatesAndCancel];
        _request = nil;
    }
    _mutex.lock();
    if (_session) {
        [_session invalidateAndCancel];
        _session = nil;
    }
    _mutex.unlock();
    self.status = MHResourceItemLoading;
    NSLog(@"GEN: start %d", (int)_index);
    [self.resource onItemRequestStart:self];
    if (self.resource.isPlaying) {
        _mutex.lock();
        if (!_session) {
            NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
            config.connectionProxyDictionary = @{};
            config.timeoutIntervalForRequest = 40;
            config.timeoutIntervalForResource = 40;
            _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:self.resource.queue];
        }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_segment.url]];
        request.timeoutInterval = 40;
        [self.resource.manager.customerHttpHeaders enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
            [request addValue:obj forHTTPHeaderField:key];
        }];
        
        NSURLSessionDataTask *dataTask = [_session dataTaskWithRequest:request];
        [dataTask resume];
        _mutex.unlock();
    }else {
        _request = [[ASIHTTPRequest alloc] initWithURL:[NSURL URLWithString:_segment.url]];
        _request.timeOutSeconds = 45;
        [_request applyProxyCredentials:@{}];
        [self.resource.manager.customerHttpHeaders enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
            [_request addRequestHeader:key value:obj];
        }];
        _request.delegate = self;
        [_request startAsynchronous];
    }
}

- (void)stop {
    [self stopWithComplete:nil];
}

- (void)stopWithComplete:(MHResourceItemOnComplete)onComplete {
    _onCompleteMutex.lock();
    if (onComplete) {
        _onCompletes.remove(onComplete);
    }
    if (!_onCompletes.size()) {
        if (self.status == MHResourceItemLoading) {
            self.status = MHResourceItemNotStart;
            if (_request) {
                [_request clearDelegatesAndCancel];
                _request = nil;
            }
            _mutex.lock();
            if (_session) {
                [_session invalidateAndCancel];
                _session = nil;
            }
            _mutex.unlock();
            [self clearMemory];
        }
    }
    _onCompleteMutex.unlock();
}

- (void)reset {
    [self stop];
    self.status = MHResourceItemNotStart;
    _diskSize = 0;
}

- (void)complete {
    NSLog(@"GEN: complete %d", (int)_index);
    @synchronized (self) {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:_resource.path]) {
            [fm createDirectoryAtPath:_resource.path
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
        }else {
            [fm setAttributes:@{NSFileModificationDate:[NSDate date]}
                 ofItemAtPath:_resource.path
                        error:nil];
        }
        _diskSize =  _buffer.size();
        if (MH_freeMemory() > MEMORY_LIMIT * MH_UNIT_MB) {
            FILE *file = fopen(_path.UTF8String, "w");
            if (file) {
                fwrite(_buffer.data(), _buffer.size(), 1, file);
                fclose(file);
                self.status = MHResourceItemComplete;
                vector<char> v;
                _buffer.swap(v);
                [_resource onItemRequestComplete:self during:[NSDate date].timeIntervalSince1970 - _startTime];
            }else {
                NSLog(@"Write file failed at %@(%ld)", _path, _buffer.size());
                [self failed:[NSError errorWithDomain:@"文件写入失败!"
                                                 code:399
                                             userInfo:nil]];
            }
        }else {
            self.status = MHResourceItemComplete;
        }
        
    }
    _onCompleteMutex.lock();
    list<MHResourceItemOnComplete> completes = _onCompletes;
    _onCompletes.clear();
    _onCompleteMutex.unlock();
    for (auto it = completes.begin(), _end = completes.end(); it != _end; ++it) {
        (*it)(nil);
    }
}

- (void)failed:(NSError *)error {
//    log_info([NSString stringWithFormat:@"下载第%d失败 %@", (int)_index, error].UTF8String);
    NSLog(@"GEN: failed %d", (int)_index);
    if (self.status == MHResourceItemLoading) {
        @synchronized (self) {
            vector<char> v;
            _buffer.swap(v);
        }
        
        /*if (self.resource.isPlaying) {
            if (_tryNum < self.resource.retryCount && (_tryNum + 1) >= self.resource.retryCount) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:MHResourceReadFailedNotification
                                                                        object:self];
                });
            }
            ++_tryNum;
            [self _start];
        }else */if (++_tryNum < self.resource.retryCount) {
//            log_info([NSString stringWithFormat:@"开始重试%d - %d", (int)_index, (int)_tryNum].UTF8String);
//            [self _start];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self _start];
            });
        }else {
            self.status = MHResourceItemFailed;
            [self.resource onItemRequestFailed:self];
            
            _onCompleteMutex.lock();
            auto completes = _onCompletes;
            _onCompletes.clear();
            _onCompleteMutex.unlock();
            for (auto it = _onCompletes.begin(), _end = _onCompletes.end(); it != _end; ++it) {
                (*it)(error);
            }
//            log_info([NSString stringWithFormat:@"下载失败 %d - %@", (int)_index, error].UTF8String);
            NSLog(@"下载失败！%@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:MHResourceReadFailedNotification
                                                                    object:self];
            });
        }
    }
}

- (void)clearCache {
    [self reset];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *path = [self.resource.path stringByAppendingPathComponent:self.segment.url.lastPathComponent];
    if ([manager fileExistsAtPath:path]) {
        [manager removeItemAtPath:path
                            error:nil];
    }
}

- (void)clearMemory {
    @synchronized (self) {
        if (_buffer.capacity() > 0) {
            vector<char> v;
            _buffer.swap(v);
            [self checkStatus];
        }
    }
    NSString *path = [self.resource.path stringByAppendingPathComponent:self.segment.url.lastPathComponent];
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:path]) {
        self.status = MHResourceItemNotStart;
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(nonnull NSURLSessionDataTask *)dataTask didReceiveResponse:(nonnull NSURLResponse *)response completionHandler:(nonnull void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields];
    _contentLength = [[headers objectForKey:@"Content-Length"] integerValue];
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(nonnull NSURLSessionDataTask *)dataTask didReceiveData:(nonnull NSData *)data {
    @synchronized (self) {
        size_t old = _buffer.size();
        _buffer.resize(old + data.length);
        memcpy(_buffer.data() + old, data.bytes, data.length);
        [self.resource onItemDownloaded:self size:data.length];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    _mutex.lock();
    if (_session) {
        [_session invalidateAndCancel];
        _session = nil;
    }
    _mutex.unlock();
    if (error) {
        [self failed:error];
    }else {
        if (_contentLength != 0 && _contentLength == _buffer.size()) {
            [self complete];
        }else {
            [self failed:[NSError errorWithDomain:@"Wrong size !"
                                             code:500
                                         userInfo:nil]];
        }
    }
}

- (void)request:(ASIHTTPRequest *)request didReceiveResponseHeaders:(NSDictionary *)responseHeaders {
    _contentLength = [[responseHeaders objectForKey:@"Content-Length"] integerValue];
}

- (void)request:(ASIHTTPRequest *)request didReceiveData:(NSData *)data {
    @synchronized (self) {
        size_t old = _buffer.size();
        NSUInteger originalSize = data.length;
        // check if http request need uncompress
        if (request.isResponseCompressed) {
            if (!_decompressor) {
                _decompressor = [ASIDataDecompressor decompressor];
            }
            data = [_decompressor uncompressBytes:(Bytef*)data.bytes length:data.length error:nil];
        }
        
        _buffer.resize(old + data.length);
        memcpy(_buffer.data() + old, data.bytes, data.length);
        [self.resource onItemDownloaded:self size:originalSize];
    }
}

- (void)requestFinished:(ASIHTTPRequest *)request {
    if (_request) {
        [_request clearDelegatesAndCancel];
        _request = nil;
    }
    if (_decompressor) {
        _decompressor = nil;
    }
    if (_contentLength == _buffer.size()) {
        [self complete];
    }else {
        [self failed:[NSError errorWithDomain:@"Wrong size !"
                                         code:500
                                     userInfo:nil]];
    }
}

- (void)requestFailed:(ASIHTTPRequest *)request {
    if (_request) {
        [_request clearDelegatesAndCancel];
        _request = nil;
    }
    if (_decompressor) {
        _decompressor = nil;
    }
    [self failed:request.error];
}

- (float)progress {
    if (_status == MHResourceItemFailed || _status == MHResourceItemNotStart) {
        return 0;
    }else if (_status == MHResourceItemComplete) {
        return 1;
    }else if (_status == MHResourceItemLoading) {
        return _contentLength == 0 ? 0 : ((float)_buffer.size() / _contentLength);
    }
    return 0;
}

@end

#define DOWNLOADING_MASK    1

@implementation MHResourceSet {
    NSRange _requestRange;
    NSMutableArray <MHResourceItem *> *_currentDownloadings;
    list<NSUInteger> _cacheSpeeds;
    
    NSUInteger _secDownloaded;
    mutex _downloadMutex;
    
    NSUInteger  _currentIndex;
    NSInteger   _onSeekIndex;
    BOOL        _onSeek;
    
    NSMutableArray<MHResourcePlayItem *> *_playItems;
    
}

- (id)initWithPath:(NSString *)path key:(NSString *)key {
    self = [super init];
    if (self) {
        _path = path;
        _key = key;
        _queue = [[NSOperationQueue alloc] init];
        _currentDownloadings = [NSMutableArray array];
        _keyStore = [[NSMutableDictionary alloc] init];
        _playItems = [[NSMutableArray alloc] init];
        _retryCount = 3;
        
        _dispatchQueue = dispatch_queue_create("ResourceSet", NULL);
        
    }
    return self;
}

- (void)setManager:(MHResourcesManager *)manager {
    _manager = manager;
}

- (void)setItems:(NSArray<MHResourceItem *> *)items {
    if (_items.count != items.count) {
        for (MHResourceItem *item in _currentDownloadings) {
            [item stop];
        }
        _items = [items copy];
        [self checkStatus];
    }
}

- (MHResourcePlayItem *)playItems:(NSArray<MHResourceItem *> * _Nonnull)items start:(BOOL)start {
    __block MHResourcePlayItem *ret = nil;
    dispatch_sync(_dispatchQueue, ^{
        if (self.items.count != items.count) {
            self.items = items;
        }
        ret = [[MHResourcePlayItem alloc] init];
        ret.resource = self;
        [self->_playItems addObject:ret];
        if (start) {
            [ret start];
        }
    });
    
    return ret;
}


- (void)onPlayerItemExit:(MHResourcePlayItem *)item {
    [_playItems removeObject:item];
}

//- (void)exitPlaying {
//    dispatch_sync(_dispatchQueue, ^{
//        self->_playCount = MAX(0, self->_playCount-1);
//        if (self->_playCount == 0) {
//            NSArray *arr;
//            @synchronized(self) {
//                arr = [self->_currentDownloadings copy];
//                [self->_currentDownloadings removeAllObjects];
//            }
//            for (MHResourceItem *item in arr) {
//                [item stop];
//            }
//            if (!(self->_rStatus & DOWNLOADING_MASK)) {
//                if (self.status != MHResourceSetComplete) {
//                    self.status = MHResourceSetIdle;
//                    if ([self.delegate respondsToSelector:@selector(resourceSet:statusChanged:)]) {
//                        [self.delegate resourceSet:self
//                                     statusChanged:self.status];
//                    }
//                }
//                [self.manager onResourceSetStoped:self];
//            }
//            self->_downloadSpeed = 0;
//            self->_cacheSpeeds.clear();
//            if ([self.delegate respondsToSelector:@selector(resourceSet:speed:)]) {
//                [self.delegate resourceSet:self
//                                     speed:self->_downloadSpeed];
//            }
//
//            for (MHResourceItem *item in self->_items) {
//                [item clearMemory];
//            }
//            if (self->_rStatus & DOWNLOADING_MASK) {
//                if (self.status != MHResourceSetDownloading) {
//                    self.status = MHResourceSetDownloading;
//                    if ([self.delegate respondsToSelector:@selector(resourceSet:statusChanged:)]) {
//                        [self.delegate resourceSet:self
//                                     statusChanged:self.status];
//                    }
//                    [self.manager onResourceSetStarted:self];
//                }
//                self->_requestRange.location = 0;
//                self->_requestRange.length = 0;
//                [self requestForward:YES];
//            }
//            self->_currentIndex = -1;
//        }
//
//    });
//
//}

- (BOOL)isPlaying {
    return _playItems.count > 0;
}

- (BOOL)isDownloading {
    return _rStatus & DOWNLOADING_MASK;
}

- (void)checkStatus {
    _completeCount = 0;
    NSInteger count = 0;
    _diskSize = 0;
    for (MHResourceItem *item in _items) {
        [item checkStatus];
        item.index = count++;
        if (item.status == MHResourceItemComplete) {
            ++_completeCount;
            _diskSize += item.diskSize;
        }
    }
    if (_completeCount == _items.count) {
        if (self.status != MHResourceSetComplete) {
            self.status = MHResourceSetComplete;
            if ([self.delegate respondsToSelector:@selector(resourceSet:statusChanged:)]) {
                [self.delegate resourceSet:self
                             statusChanged:self.status];
            }
        }
    }else {
        if (self.status != MHResourceSetIdle && !self.isPlaying) {
            self.status = MHResourceSetIdle;
            if ([self.delegate respondsToSelector:@selector(resourceSet:statusChanged:)]) {
                [self.delegate resourceSet:self
                             statusChanged:self.status];
            }
        }
    }
}


//- (int)requirePlay:(NSInteger)index {
//    NSLog(@"SEEK: requirePlay %d!", (int)index);
//    if (!self.isPlaying) {
//        return -1;
//    }
//    if (_onSeek) {
//        return -1;
//    }
//    if (index < _items.count) {
//        if (_currentIndex != index) {
//            MHResourceItem *old = _currentIndex < _items.count ? [_items objectAtIndex:_currentIndex] : nil;
//            [old clearMemory];
//            _currentIndex = index;
//        }
//        if (index >= _requestRange.location && index <= _requestRange.location + _requestRange.length) {
//            MHResourceItem *item = [_items objectAtIndex:index];
//            if (item.status == MHResourceItemFailed || item.status == MHResourceItemNotStart) {
//                _requestRange.length = index - _requestRange.location;
//                [self requestForward:YES];
//            }else {
//                [self requestForward:NO];
//            }
//        }else {
//            _requestRange.location = index;
//            _requestRange.length = 0;
//            [self requestForward:YES];
//        }
//    }
//    return 0;
//}

- (void)checkDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:_path]) {
        [fm createDirectoryAtPath:_path withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];
    }
}

- (BOOL)loadItemsFromDisk:(NSString *)url {
    NSString *infoPath = [self.path stringByAppendingPathComponent:[NSURL URLWithString:url].lastPathComponent];
    if ([[NSFileManager defaultManager] fileExistsAtPath:infoPath]) {
        NSData *data = [NSData dataWithContentsOfFile:infoPath];
        NSArray<IJKHLSSegment *> *segments = m3u8::parse_hls((const char *)data.bytes, data.length, url.UTF8String);
        NSMutableArray *arr = [NSMutableArray array];
        for (IJKHLSSegment *seg in segments) {
            MHResourceItem *item = [[MHResourceItem alloc] initWithResource:self
                                                                    segment:seg];
            [arr addObject:item];
        }
        self.items = arr;
        return YES;
    }
    return NO;
}

- (void)onPause {
    NSArray *arr;
    @synchronized(self) {
        arr = [_currentDownloadings copy];
    }
    for (MHResourceItem *item in arr) {
        [item reset];
    }
    [_currentDownloadings removeAllObjects];
    [_queue cancelAllOperations];
}

- (void)_stop {
    if (self.status == MHResourceSetDownloading) {
        NSArray *arr;
        @synchronized(self) {
            arr = [_currentDownloadings copy];
        }
        for (MHResourceItem *item in arr) {
            [item stop];
        }
        [_currentDownloadings removeAllObjects];
        [_queue cancelAllOperations];
        self.status = MHResourceSetIdle;
        if ([self.delegate respondsToSelector:@selector(resourceSet:statusChanged:)]) {
            [self.delegate resourceSet:self
                         statusChanged:self.status];
        }
        [self.manager onResourceSetStoped:self];
        _downloadSpeed = 0;
        _cacheSpeeds.clear();
        
        if ([self.delegate respondsToSelector:@selector(resourceSet:speed:)]) {
            [self.delegate resourceSet:self speed:_downloadSpeed];
        }
    }
}

- (void)stop {
    [self _stop];
    if (self.status != MHResourceSetDownloading) {
        if (_rStatus & DOWNLOADING_MASK) {
            _rStatus ^= DOWNLOADING_MASK;
        }
    }
}

- (void)_start {
    if (_items.count && (self.status == MHResourceSetIdle || self.status == MHResourceSetFailed)) {
        self.status = MHResourceSetDownloading;
        if ([self.delegate respondsToSelector:@selector(resourceSet:statusChanged:)]) {
            [self.delegate resourceSet:self
                         statusChanged:self.status];
        }
        [self requestForward];
        [self.manager onResourceSetStarted:self];
    }
}

- (void)start {
    [self _start];
    if (self.status == MHResourceSetDownloading) {
        if (!(_rStatus & DOWNLOADING_MASK)) {
            _rStatus ^= DOWNLOADING_MASK;
        }
    }
    
}

- (NSData *)keyStore:(NSString *)url {
    NSData *data = [_keyStore objectForKey:url];
    if (data) {
        return data;
    }
    NSString *path = [self.path stringByAppendingPathComponent:url.lastPathComponent];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        data = [NSData dataWithContentsOfFile:path];
        [_keyStore setObject:data forKey:url];
    }else {
        ASIHTTPRequest *request = [[ASIHTTPRequest alloc] initWithURL:[NSURL URLWithString:url]];
        [request startSynchronous];
        if (!request.error) {
            data = request.responseData;
            [data writeToFile:path atomically:YES];
            [_keyStore setObject:data forKey:url];
        }
    }
    return data;
}

- (void)onSeek {
    return;
    _onSeek = YES;
    NSArray *arr;
    @synchronized(self) {
        arr = [_currentDownloadings copy];
        [_currentDownloadings removeAllObjects];
    }
    for (MHResourceItem *item in arr) {
        [item stop];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(seekComplete)
                                                 name:IJKMPMoviePlayerDidSeekCompleteNotification
                                               object:nil];
}
- (MHResourcePlayItem *)getPlayItemWithNumber:(NSInteger)number {
    for (MHResourcePlayItem *item in _playItems) {
        if (item.playerNumber == number) {
            return item;
        }
    }
    return nil;
}

- (void)seekComplete {
    _onSeek = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:IJKMPMoviePlayerDidSeekCompleteNotification
                                                  object:nil];
}

- (float)progress {
    if (self.items.count == 0) {
        return 0;
    }
    float currentProgress = (float)self.completeCount / self.items.count;
    float addprogress = 0;
    for (MHResourceItem *item in _currentDownloadings) {
        addprogress += item.progress / self.items.count;
    }
    return MIN(1, MAX(0, currentProgress + addprogress));
}

- (void)loadItemsFromUrl:(NSString *)url
                   block:(void(^)(BOOL))block {
    [self loadItemsFromUrl:url
               loaderClass:nil
                     block:block];
}

- (void)loadItemsFromUrl:(NSString *)url
             loaderClass:(Class  _Nullable __unsafe_unretained)loaderClass
                   block:(nonnull void (^)(BOOL))block {
    if (!loaderClass) {
        loaderClass = MHM3U8Loader.class;
    }
    MHM3U8Loader *requestTask = [[loaderClass alloc] initWithResources:self
                                                                  queue:self.queue];
    [requestTask open:url];
    dispatch_queue_t q = dispatch_queue_create("dispath", NULL);
    dispatch_async(q, ^{
        vector<char> tmp;
#define BUFFER_SIZE 4096
        char buf[BUFFER_SIZE];
        while (true) {
            int r = [requestTask readData:buf size:BUFFER_SIZE];
            if (r > 0) {
                size_t old = tmp.size();
                tmp.resize(old + r);
                memcpy(tmp.data() + old, buf, r);
            }else {
                break;
            }
        }
        NSArray<IJKHLSSegment *> *segments = m3u8::parse_hls(tmp.data(), tmp.size(), url.UTF8String);
        if (segments.count) {
            NSMutableArray *arr = [NSMutableArray array];
            for (IJKHLSSegment *seg in segments) {
                MHResourceItem *item = [[MHResourceItem alloc] initWithResource:self
                                                                        segment:seg];
                [arr addObject:item];
            }
            self.items = arr;
            if (block) {
                block(YES);
            }
        }else {
            self.items = nil;
            if (block) {
                block(NO);
            }
        }
    });
}

- (void)clearCache {
    if (self.isPlaying) {
        NSLog(@"Warring can not clear cache for a playing resources.");
        return;
    }
    for (MHResourceItem *item in _items) {
        [item reset];
    }
    [self stop];
    if (self.status == MHResourceSetComplete) {
        self.status = MHResourceSetIdle;
        if ([self.delegate respondsToSelector:@selector(resourceSet:statusChanged:)]) {
            [self.delegate resourceSet:self statusChanged:_status];
        }
    }
    [[NSFileManager defaultManager] removeItemAtPath:self.path
                                               error:nil];
    _diskSize = 0;
    _completeCount = 0;
}

- (void)dealloc {
    [_manager removeResource:_key];
    self.items = nil;
}

- (void)startDownloadItem:(MHResourceItem *)item {
    if (self.isPlaying || MH_freeMemory() > MEMORY_LIMIT * MH_UNIT_MB) {
        [item start];
    }
}

- (void)requestForward {
    [self requestForward:NO];
}

- (void)requestForward:(BOOL)playing {
    if (self.status != MHResourceSetDownloading) {
        return;
    }
    if (!playing && _currentDownloadings.count >= 1) {
        return;
    }
    while (true) {
        NSInteger off = _requestRange.location + _requestRange.length;
        if (off >= _items.count) {
            for (NSInteger i = 0, t = _items.count; i < t; ++i) {
                MHResourceItem *item = [_items objectAtIndex:i];
                if (item.status != MHResourceItemComplete) {
                    _requestRange.location = 0;
                    _requestRange.length = i + 1;
                    
                    if (item.status == MHResourceItemNotStart || item.status == MHResourceItemFailed) {
                        [self startDownloadItem:item];
                    }
                    return;
                }
            }
            // 加载完成
            _completeCount = _items.count;
            self.status = MHResourceSetComplete;
            if ([self.delegate respondsToSelector:@selector(resourceSet:statusChanged:)]) {
                [self.delegate resourceSet:self statusChanged:_status];
            }
            _downloadSpeed = 0;
            _cacheSpeeds.clear();
            if ([self.delegate respondsToSelector:@selector(resourceSet:speed:)]) {
                [self.delegate resourceSet:self
                                     speed:_downloadSpeed];
            }
            [self.manager onResourceSetStoped:self];
            return;
        }
        MHResourceItem *item = [_items objectAtIndex:off];
        _requestRange.length++;
        if (item.status == MHResourceItemComplete) {
            continue;
        }else if (item.status == MHResourceItemNotStart || item.status == MHResourceItemFailed) {
            [self startDownloadItem:item];
            break;
        }else {
            break;
        }
    }
}

#define CACHE_SIZE 6

- (void)onClock {
    _downloadMutex.lock();
    NSUInteger s = _secDownloaded;
    _secDownloaded = 0;
    _downloadMutex.unlock();
    
    _cacheSpeeds.push_back(s);
    while (_cacheSpeeds.size() > CACHE_SIZE) {
        _cacheSpeeds.erase(_cacheSpeeds.begin());
    }
    NSUInteger speed = 0;
    for (auto it = _cacheSpeeds.begin(), _e = _cacheSpeeds.end(); it != _e; ++it) {
        speed += *it;
    }
    speed /= _cacheSpeeds.size();
    if (_downloadSpeed != speed) {
        _downloadSpeed = speed;
        if ([self.delegate respondsToSelector:@selector(resourceSet:speed:)]) {
            [self.delegate resourceSet:self speed:speed];
        }
    }
}

- (void)onItemDownloaded:(MHResourceItem *)item size:(NSUInteger)size {
    _downloadMutex.lock();
    _secDownloaded += size;
    _downloadMutex.unlock();
    
    if ([self.delegate respondsToSelector:@selector(resourceSet:progress:)]) {
        [self.delegate resourceSet:self progress:self.progress];
    }
}

- (void)onItemRequestStart:(MHResourceItem *)item {
    @synchronized (_currentDownloadings) {
        [_currentDownloadings addObject:item];
    }
}

- (void)onItemRequestComplete:(MHResourceItem *)item during:(NSTimeInterval)during {
    @synchronized (_currentDownloadings) {
        [_currentDownloadings removeObject:item];
    }
    ++_completeCount;
    _diskSize += item.diskSize;
    if ([self.delegate respondsToSelector:@selector(resourceSet:itemComplete:)]) {
        [self.delegate resourceSet:self itemComplete:item];
    }
    if (self.status == MHResourceSetDownloading) {
        [self requestForward];
    }
}

- (void)onItemRequestFailed:(MHResourceItem *)item {
    @synchronized (_currentDownloadings) {
        [_currentDownloadings removeObject:item];
    }
    if (self.status == MHResourceSetDownloading) {
        if (self.isPlaying) {
            // Do nothing when playing.
        }else {
            self.status = MHResourceSetFailed;
            if ([self.delegate respondsToSelector:@selector(resourceSet:statusChanged:)]) {
                [self.delegate resourceSet:self
                             statusChanged:self.status];
            }
            [self.manager onResourceSetStoped:self];
        }
    }
}

@end

@implementation MHResourcesManager {
    NSString    *_cachePath;
    NSMutableDictionary *_resources;
    NSTimer *_time;
    NSMutableDictionary *_currentDownloading;
    NSMutableDictionary *_maskkeys;
    
    UITextView *_logContentView;
    UIButton *_logCloseButton;
}

static MHResourcesManager *MHResourcesManager_manager = nil;

+ (instancetype)instance {
    @synchronized (self) {
        if (!MHResourcesManager_manager) {
            MHResourcesManager_manager = [[MHResourcesManager alloc] init];
        }
        return MHResourcesManager_manager;
    }
}

- (id)init {
    self = [super init];
    if (self) {
        _time = [NSTimer timerWithTimeInterval:1
                                        target:self
                                      selector:@selector(onClock)
                                      userInfo:nil
                                       repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_time
                                  forMode:NSDefaultRunLoopMode];
        _currentDownloading = [NSMutableDictionary dictionary];
        _preloadCount = 10;
        _resources = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    NSLog(@"dealloc!");
}

- (void)setBandwidthLimit:(NSUInteger)bandwidthLimit {
    _bandwidthLimit = bandwidthLimit;
    [ASIHTTPRequest setMaxBandwidthPerSecond:bandwidthLimit];
}

- (void)setup:(NSString *)path {
    _cachePath = path;
}

- (MHResourceSet *)resourcesFromKey:(NSString *)key {
    if (!_cachePath) {
        _cachePath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"videos"];
    }
    @synchronized (self) {
        MHResourceSet *resource = [_resources objectForKey:key];
        if (!resource) {
            NSString *rPath = [NSString stringWithFormat:@"%@/%@", _cachePath, md5String(key)];
            MHResourceSet *set = [[MHResourceSet alloc] initWithPath:rPath key:key];
            set.manager = self;
            [_resources setObject:set
                           forKey:key];
            return set;
        }
        return resource;
    }
}

- (NSString *)keyFromURL:(NSURL *)url {
    if (!url) {
        return nil;
    }
    NSMutableString *key = [NSMutableString stringWithFormat:@"%@://%@", url.scheme, url.host];
    if (url.port) {
        [key appendFormat:@":%@", url.port];
    }
    [key appendString:url.path];
    return key;
}

- (MHResourceSet *)resourcesFromURL:(NSURL *)url {
    if (!url) {
        return nil;
    }
    return [self resourcesFromKey:[self keyFromURL:url]];
}

- (void)removeResource:(NSString *)key {
    @synchronized (self) {
        [_resources removeObjectForKey:key];
    }
}

- (void)onClock {
    [_resources enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        MHResourceSet *res = obj;
        if (res.isDownloading || res.isPlaying) {
            [res onClock];
        }
    }];
}

- (void)onResourceSetStarted:(MHResourceSet *)resources {
    @synchronized (_currentDownloading) {
        [_currentDownloading setObject:resources forKey:resources.key];
    }
}

- (void)onResourceSetStoped:(MHResourceSet *)resources {
    @synchronized (_currentDownloading) {
        [_currentDownloading removeObjectForKey:resources.key];
    }
}

- (void)setMaskkey:(NSUInteger)maskkey forKey:(NSString *)key {
    if (!key) {
        return;
    }
    if (!_maskkeys) {
        _maskkeys = [NSMutableDictionary dictionary];
    }
    [_maskkeys setObject:[NSNumber numberWithUnsignedInteger:maskkey]
                  forKey:key];
}

- (void)setMaskkey:(NSUInteger)maskkey forURL:(NSURL *)url {
    [self setMaskkey:maskkey forKey:[self keyFromURL:url]];
}

- (void)clearAllMaskkeys {
    [_maskkeys removeAllObjects];
}

- (void)setAESkey:(NSString *)aeskey forKey:(NSString *)key {
    [MHPrivateM3U8Loader setKey:aeskey forUrl:key];
}

- (void)setAESkey:(NSString *)aeskey forURL:(NSURL *)url {
    [self setAESkey:aeskey forKey:[self keyFromURL:url]];
}

- (NSNumber *)maskkeyForKey:(NSString *)key {
    return [_maskkeys objectForKey:key];
}

- (void)clearAllAESkeys {
    [MHPrivateM3U8Loader clearAllKeys];
}

namespace mh {
    
    struct DirInfo {
        string path;
        uint8_t type;
        time_t mtime;
        
        DirInfo(const char * path,
                uint8_t type,
                time_t mtime) : path(path), type(type), mtime(mtime) {
            
        }
    };
    
    bool isInWhiteList(const char *str, const vector<string> &whiteList) {
        for (auto it = whiteList.begin(), _e = whiteList.end(); it != _e; ++it) {
            if (strcmp(str, (*it).c_str()) == 0) {
                return true;
            }
        }
        return false;
    }
    
    struct Comare {
        const string *want_path;
        
        Comare(const string &want_path) : want_path(&want_path) {
            
        }
        
        bool operator()(const mh::DirInfo &d1, const mh::DirInfo &d2) {
            if (d1.path == *want_path) {
                return true;
            }else if (d2.path == *want_path) {
                return false;
            }else
                return d1.mtime > d2.mtime;
        }
    };
}


- (void)clearCache:(NSUInteger)limitSize whiteList:(NSArray<NSURL *> * _Nullable)whiteList wantUrl:(NSURL * _Nullable)url {
    if (!_cachePath) {
        _cachePath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"videos"];
    }
    
    NSLog(@"nihao clear cache!");
    
    NSMutableDictionary<NSString *, MHResourceSet *> *cacheMap = [NSMutableDictionary dictionary];
    @synchronized (self) {
        [_resources enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            MHResourceSet *res = obj;
            if (res) {
                @try {
                    [cacheMap setObject:res forKey:c_md5String(key)];
                }
                @catch (NSException *e) {
                    NSLog(@"%@", e);
                }
            }
        }];
    }

    vector<string> whites(whiteList.count);
    if (whiteList.count) {
        for (NSURL *url in whiteList) {
            @try {
                whites.push_back(c_md5String([self keyFromURL:url]).UTF8String);
            } @catch (NSException *exception) {
                NSLog(@"%@", exception);
            } @finally {
            }
        }
    }
    string wantPath;
    if (url) {
        @try {
            wantPath =  c_md5String([self keyFromURL:url]).UTF8String;
        } @catch (NSException *exception) {
            NSLog(@"%@", exception);
        }
    }

    std::list<mh::DirInfo> dir_list;
    const char *dirpath = _cachePath.UTF8String;

    DIR *dir = opendir(_cachePath.UTF8String);
    if (!dir) return;
#define MAX_SIZE 4096
    char childpath[MAX_SIZE];
    struct dirent *ent;
    while ((ent = readdir(dir))) {
        if (ent->d_name[0] != '.' && !mh::isInWhiteList(ent->d_name, whites)) {
            sprintf(childpath, "%s/%s", dirpath, ent->d_name);
            struct stat st;
            stat(childpath, &st);
            dir_list.push_back(mh::DirInfo(childpath, ent->d_type, st.st_mtime));
        }
    }
    dir_list.sort(mh::Comare(wantPath));
    NSUInteger _currentSize = 0;
    NSUInteger _deleteSize = 0;

    for (auto it = dir_list.begin(), _e = dir_list.end(); it != _e; ++it) {

        DIR *dir = opendir(it->path.c_str());
        if (!dir) continue;
        struct dirent *ent;
        bool isDelete = false;
        while ((ent = readdir(dir))) {
            if (ent->d_name[0] != '.') {
                sprintf(childpath, "%s/%s", it->path.c_str(), ent->d_name);
                struct stat st;
                stat(childpath, &st);
                if (_currentSize + st.st_size > limitSize && it->path != wantPath) {
                    if (ent->d_type != DT_DIR) {
                        _deleteSize += st.st_size;
                        unlink(childpath);
                        isDelete = true;
                    }
                }else {
                    _currentSize += st.st_size;
                }
            }
        }
        closedir(dir);
        if (isDelete) {
            string name = it->path.substr(it->path.find_last_of('/') + 1);
            MHResourceSet *resource = [cacheMap objectForKey:[NSString stringWithUTF8String:name.c_str()]];
            [resource checkStatus];
        }
    }
    closedir(dir);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:MHResourceManagerClearCacheNotification
                                                        object:self
                                                      userInfo:@{
                                                                 MHResourceManagerKeepKey: [NSNumber numberWithUnsignedInteger:_currentSize],
                                                                 MHResourceManagerDeleteKey: [NSNumber numberWithUnsignedInteger:_deleteSize]
                                                                 }];
}

- (void)refreshNetwork {
    [[NSNotificationCenter defaultCenter] postNotificationName:MHResourceReadRefreshNotification
                                                        object:nil];
}

- (NSDictionary<NSString *, NSString *> *)customerHttpHeaders {
    return _customerHttpHeaders;
}

- (void)setCustomerHttpHeaders:(NSDictionary<NSString *,NSString *> *)headers {
    _customerHttpHeaders = headers;
}

- (void)showLogs {
    
    NSString *filePath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"logs/log.log"];
    NSString *content = [NSString stringWithContentsOfFile:filePath
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    UIWindow *window = [UIApplication sharedApplication].delegate.window;
    CGRect bounds = [UIScreen mainScreen].bounds;
    UITextView *textview = [[UITextView alloc] initWithFrame:bounds];
    textview.text = content;
    [window addSubview:textview];
    
    _logContentView = textview;
    
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(bounds.size.width-40, 20, 40, 40)];
    button.backgroundColor = [UIColor redColor];
    [button addTarget:self
               action:@selector(closeTextView)
     forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:button];
    _logCloseButton = button;
}


- (void)closeTextView {
    [_logContentView removeFromSuperview];
    [_logCloseButton removeFromSuperview];
}

@end


extern NSString * const MHResourceSwapNotification = @"MHResourceSwap";
extern NSString * const MHResourceM3U8URLExpireNotification = @"MHResourceM3U8URLExpire";
extern NSString * const MHResourceReadFailedNotification = @"MHResourceReadFailed";
extern NSString * const MHResourceManagerClearCacheNotification = @"MHResourceManagerClearCache";
extern NSString * const MHResourceManagerKeepKey = @"keep";
extern NSString * const MHResourceManagerDeleteKey = @"delete";
