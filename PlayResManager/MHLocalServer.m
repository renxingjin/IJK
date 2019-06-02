//
//  MHLocalServer.m
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/6.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import "MHLocalServer.h"
#import "tmd5.h"
#import "MHResourcesManager.h"
#import "utils/aes.h"
#import "loaders/MHProxyM3U8Loader.h"
#include <ifaddrs.h>
#include <sys/socket.h>
#include <arpa/inet.h>

@interface MHIPItem : NSObject

@property (nonatomic, strong) NSString *ipAddress;
@property (nonatomic, strong) NSString *ifaName;

@end

@implementation MHIPItem

@end

@interface MHServerRequest : GCDWebServerRequest

@property (nonatomic, strong) MHServerItem *item;
@property (nonatomic, strong) NSString *filename;

@end

@implementation MHServerRequest

@end

@interface MHServerItem ()

@property (nonatomic, readonly) MHResourceSet *resources;
@property (nonatomic, readonly) MHResourcePlayItem *playItem;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSNumber *> *index;

- (void)runWithItems:(NSArray *)items;
- (void)exit;

- (void)loadM3u8:(void(^)(NSData *))block;

@end

@implementation MHServerItem

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _url = url;
        _resources = [[MHResourcesManager instance] resourcesFromURL:url];
        _md5 = [_resources.path lastPathComponent];
    }
    return self;
}

- (void)runWithItems:(NSArray *)items {
    _index = [NSMutableDictionary dictionary];
    for (NSInteger i = 0, t = items.count; i < t; ++i) {
        MHResourceItem *item  = [items objectAtIndex:i];
        [_index setObject:[NSNumber numberWithInteger:i]
                   forKey:item.segment.url.lastPathComponent];
    }
    _playItem = [self.resources playItems:items start:YES];
    _playItem.playerNumber = MH_SERVER_PLAYER_NUMBER;
}

- (void)exit {
    [_playItem exitPlaying];
}

- (void)loadM3u8:(void(^)(NSData *))block {
    MHProxyM3U8Loader *loader = [[MHProxyM3U8Loader alloc] initWithResources:_resources
                                                                       queue:_resources.queue];
    [loader open:_url.absoluteString];
    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        NSData *data = [loader loadAll];
        block(data);
    }];
    [thread start];
}

@end

@interface MHLocalServer ()

@property (nonatomic, readonly) NSMutableDictionary<NSString *, MHServerItem *> *items;

@end

@implementation MHLocalServer {
}

- (id)init {
    self = [super init];
    if (self) {
        MHLocalServer *this = self;
        [self addHandlerWithMatchBlock:^GCDWebServerRequest * _Nullable(NSString * _Nonnull requestMethod, NSURL * _Nonnull requestURL, NSDictionary * _Nonnull requestHeaders, NSString * _Nonnull urlPath, NSDictionary * _Nonnull urlQuery) {
            NSArray *arr = [urlPath componentsSeparatedByString:@"/"];
            if (arr.count == 3) {
                NSString *md5 = [arr objectAtIndex:1];
                NSString *filename = [arr objectAtIndex:2];
                MHServerItem *item = [this.items objectForKey:md5];
                if (item) {
                    MHServerRequest *request = [[MHServerRequest alloc] init];
                    request.item = item;
                    request.filename = filename;
                    return request;
                }
            }
            return nil;
        } asyncProcessBlock:^(__kindof GCDWebServerRequest * _Nonnull request, GCDWebServerCompletionBlock  _Nonnull completionBlock) {
            [this asyncProcessBlock:request complete:^(GCDWebServerResponse *response){
                [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];
                completionBlock(response);
            }];
        }];
    }
    return self;
}

- (void)dealloc {
    NSLog(@"dealloc");
}

- (void)startItem:(MHServerItem *)item loaderClass:(Class)loaderClass block:(MHServerStartBlock _Nullable)block {
    if (!_items) {
        _items = [NSMutableDictionary dictionary];
    }
    [_items setObject:item forKey:item.md5];
    [item.resources loadItemsFromUrl:item.url.absoluteString loaderClass:loaderClass block:^(BOOL ret){
        if (ret) {
            [item runWithItems:item.resources.items];
            if (block) {
                block(item.resources.items);
            }
        }else {
            if (block) {
                block(nil);
            }
        }
    }];
    if (!self.isRunning) {
        [self start];
    }
}

- (void)startItem:(MHServerItem *)item block:(MHServerStartBlock _Nullable)block {
    [self startItem:item loaderClass:nil block:block];
}

- (void)stopItem:(MHServerItem *)item {
    [item exit];
    [_items removeObjectForKey:item.md5];
    if (_items.count == 0) {
        [self stop];
    }
}

- (void)asyncProcessBlock:(__kindof GCDWebServerRequest * _Nonnull) request complete:(GCDWebServerCompletionBlock _Nullable)completionBlock {
    MHServerRequest *req = request;
    if ([[req.item.url lastPathComponent] isEqualToString:req.filename]) {
        [req.item loadM3u8:^(NSData *data) {
            if (data) {
                completionBlock([[GCDWebServerDataResponse alloc] initWithData:data
                                                                   contentType:@"aplication/stream"]);
            }else {
                completionBlock([GCDWebServerResponse responseWithStatusCode:500]);
            }
        }];
    }else {
        NSNumber *number = [req.item.index objectForKey:req.filename];
        if (number) {
            NSInteger index = [number integerValue];
            [req.item.playItem requirePlay:index];
            MHResourceItem *item = [req.item.resources.items objectAtIndex:index];
            if (req.hasByteRange && (req.byteRange.location % AES_BLOCKLEN) == 0 && (req.byteRange.length % AES_BLOCKLEN) == 0 && req.byteRange.length != 0) {
                char *bytes = malloc(req.byteRange.length);
                int len = [item readData:(uint8_t*)bytes size:(int)req.byteRange.length offset:req.byteRange.location];
                if (len <= 0) {
                    completionBlock([GCDWebServerResponse responseWithStatusCode:500]);
                    return;
                }
                NSData *responseData = [NSData dataWithBytes:bytes length:len];
                free(bytes);
                GCDWebServerDataResponse *response = [[GCDWebServerDataResponse alloc] initWithData:responseData
                                                                                        contentType:@"aplication/stream"];
                [response setValue:[NSString stringWithFormat:@"bytes %d-%d/*", (int)req.byteRange.location, len] forAdditionalHeader:@"Content-Range"];
                completionBlock(response);
            }else {
                // Read all?
                NSData *data = item.readAllData;
                if (data) {
                    completionBlock([[GCDWebServerDataResponse alloc] initWithData:data
                                                                       contentType:@"aplication/stream"]);
                }else {
                    completionBlock([GCDWebServerResponse responseWithStatusCode:500]);
                }
            }
        }else {
            completionBlock([GCDWebServerResponse responseWithStatusCode:404]);
        }
    }
}

+ (NSArray<NSString *> *)ipAddresses {
    struct ifaddrs *interfaces = NULL;
    NSMutableArray *arr = [NSMutableArray array];
    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *it = interfaces;
        while (it) {
            if (it->ifa_addr->sa_family == AF_INET) {
                NSString *ipAdd = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)it->ifa_addr)->sin_addr)];
                if (![ipAdd hasPrefix:@"127"] && ![ipAdd hasPrefix:@"255"] && ![arr containsObject:ipAdd]) {
                    
                    NSLog(@"%s", it->ifa_name);
                    MHIPItem *item = [[MHIPItem alloc] init];
                    item.ifaName = [NSString stringWithUTF8String:it->ifa_name];
                    item.ipAddress = ipAdd;
                    [arr addObject:item];
                }
            }
            it = it->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    [arr sortUsingComparator:^NSComparisonResult(MHIPItem*  _Nonnull obj1, MHIPItem*  _Nonnull obj2) {
        if ([obj1.ifaName isEqualToString:@"en0"]) {
            return NSOrderedAscending;
        }
        return [obj1.ifaName compare:obj2.ifaName];
    }];
    NSMutableArray *ips = [NSMutableArray arrayWithCapacity:arr.count];
    for (MHIPItem *item in arr) {
        [ips addObject:item.ipAddress];
    }
    return ips;
}

@end
