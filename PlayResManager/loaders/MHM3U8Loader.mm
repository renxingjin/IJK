//
//  MHM3U8Loader.m
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/6.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import "MHM3U8Loader.h"
#include <vector>
#import "MHResourcesManager.h"
#import "../MHResourcesManager_private.h"
#import "../utils/m3u8_parser.h"

@interface MHM3U8Loader () <NSURLSessionDataDelegate>

@end

using namespace std;

static MHPlaylistValidater MHPlaylistValidater_validater = NULL;

typedef enum : NSUInteger {
    MHRequestReadLine,
    MHRequestReadRange,
} MHRequestType;

@implementation MHM3U8Loader {
    dispatch_semaphore_t _semaphore;
    NSOperationQueue    *_taskQueue;
    NSURLSession    *_session;
    MHRequestType   _requestType;
    NSURL *_url;
    NSString *_filePath;
    
    NSMutableData   *_content;
    
    BOOL _active;
    // 0 none 1 loading 2 complete 3 failed
    NSInteger _state;
    
    
    const char *_readBuffer;
    size_t _readLength;
    BOOL _readActive;
    size_t _readOffset;
    NSURLSessionDataTask *_dataTask;
    
}

- (id)initWithResources:(MHResourceSet *)resources queue:(NSOperationQueue *)queue {
    self = [super init];
    if (self) {
        _taskQueue = queue;
        _resources = resources;
        _content = [NSMutableData data];
    }
    return self;
}

- (void)open:(NSString *)url {
    if (_active) {
        return;
    }
    _url = [NSURL URLWithString:url];
    _active = YES;
    _readOffset = 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:_resources.path]) {
        [fm createDirectoryAtPath:_resources.path
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];
    }
    _filePath = [_resources.path stringByAppendingPathComponent:[_url lastPathComponent]];
    if ([fm fileExistsAtPath:_filePath]) {
        _state = 2;
        _content = [self processData:[NSMutableData dataWithContentsOfFile:_filePath]];
    }else {
        _semaphore = dispatch_semaphore_create(0);
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:_taskQueue];
        _content = [NSMutableData data];
        NSURLSessionDataTask *dataTask = [_session dataTaskWithURL:_url];
        [dataTask resume];
        _state = 1;
    }
}

- (int)readLine:(char *)buf size:(size_t)size {
    while (true) {
        if (_state == 3) {
            break;
        }else if (_state == 2) {
            int off = 0;
            char *content  = (char *)_content.bytes;
            while (off < (size - 1) && off + _readOffset < _content.length) {
                char ch = content[_readOffset + off];
                if (ch == '\n') {
                    _readOffset += 1;
                    break;
                }else {
                    buf[off] = ch;
                }
                off ++;
            }
            buf[off] = '\0';
            _readOffset += off;
            return off;
        }else {
            dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
        }
    }
    return 0;
}
- (int)readData:(char *)buf size:(size_t)size {
    while (true) {
        if (_state == 3) {
            break;
        }else if (_state == 2) {
            size_t len = MIN(_content.length - _readOffset, size);
            if (len > 0) {
                char *buffer = (char *)_content.bytes;
                memcpy(buf, buffer + _readOffset, len);
                _readOffset += len;
                return (int)len;
            }
            return 0;
        }else {
            dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
        }
    }
    return 0;
}

- (NSData *)loadAll {
    while (true) {
        if (_state == 3) {
            break;
        }else if (_state == 2) {
            return _content;
        }else {
            dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
        }
    }
    return nil;
}

- (NSUInteger)seek:(NSUInteger)offset whence:(int)whence {
    switch (whence) {
        case SEEK_CUR:
            _readOffset = MIN(offset+_readOffset, _content.length - 1);
            return _readOffset;
            break;
        case SEEK_SET:
            _readOffset = offset;
            return _readOffset;
        case SEEK_END:
            _readOffset = MAX(0, offset+_readOffset);
            return _readOffset;
            
        default:
            break;
    }
    return 0;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(nonnull NSURLResponse *)response completionHandler:(nonnull void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields];
    NSString *token = [headers objectForKey:@"X-Token-Expire"];
    if (!token) {
        token = [headers objectForKey:@"x-token-expire"];
    }
    if ([token integerValue] != 0) {
        _state = 3;
        completionHandler(NSURLSessionResponseCancel);
        dispatch_semaphore_signal(_semaphore);
        [[NSNotificationCenter defaultCenter] postNotificationName:MHResourceM3U8URLExpireNotification
                                                            object:_url];
    }else {
        completionHandler(NSURLSessionResponseAllow);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [_content appendData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error {
    [_session invalidateAndCancel];
    _session = nil;
    if (error) {
        _state = 3;
        dispatch_semaphore_signal(_semaphore);
    }else {
        NSString *str = [[NSString alloc] initWithData:_content encoding:NSUTF8StringEncoding];
        if (!str) {
            _state = 3;
            dispatch_semaphore_signal(_semaphore);
            return;
        }
        NSArray<IJKHLSSegment *>* arr = m3u8::parse_hls(str.UTF8String, strlen(str.UTF8String), _url.absoluteString.UTF8String);
        
        if (MHPlaylistValidater_validater && !MHPlaylistValidater_validater(arr) || arr.count == 0) {
            _state = 3;
            [[NSNotificationCenter defaultCenter] postNotificationName:MHResourceM3U8URLExpireNotification
                                                                object:_url];
        }else {
            [_content writeToFile:_filePath
                       atomically:YES];
            _content = [self processData:_content];
            _state = 2;
        }
        dispatch_semaphore_signal(_semaphore);
    }
}


+ (void)setPlaylistValidate:(MHPlaylistValidater)validater {
    MHPlaylistValidater_validater = validater;
}

- (void)restart {
    if (_session) {
        [_session invalidateAndCancel];
        _session = nil;
    }
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.connectionProxyDictionary = @{};
    _session = [NSURLSession sessionWithConfiguration:config
                                             delegate:self
                                        delegateQueue:_taskQueue];
    _content = [NSMutableData data];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_url];
    [[MHResourcesManager instance].customerHttpHeaders enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
        [request addValue:obj forHTTPHeaderField:key];
    }];
    
    NSURLSessionDataTask *dataTask = [_session dataTaskWithURL:_url];
    [dataTask resume];
    _state = 1;
}

- (void)cancel {
    [_session invalidateAndCancel];
    _session = nil;
}

- (NSMutableData *)processData:(NSMutableData *)data {
    return data;
}

@end
