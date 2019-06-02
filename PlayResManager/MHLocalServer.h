//
//  MHLocalServer.h
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/6.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GCDWebServers/GCDWebServers.h>

NS_ASSUME_NONNULL_BEGIN

#define MH_SERVER_PLAYER_NUMBER 0x9989

@class MHResourceItem;

typedef void (^MHServerStartBlock)(NSArray<MHResourceItem *> * segments);

@interface MHServerItem : NSObject

@property (nonatomic, readonly) NSString *md5;
@property (nonatomic, readonly) NSURL *url;

- (instancetype)initWithURL:(NSURL *)url;

@end

@interface MHLocalServer : GCDWebServer

/**
 * 开始一个服务器项目
 * @param item 服务器项目
 * @param loaderClass 一个MHM3U8Loader或其子类，default: MHM3U8Loader
 */
- (void)startItem:(MHServerItem *)item loaderClass:(Class _Nullable)loaderClass block:(MHServerStartBlock _Nullable)block;
- (void)startItem:(MHServerItem *)item block:(MHServerStartBlock _Nullable)block;

- (void)stopItem:(MHServerItem *)item;

+ (NSArray<NSString *> *)ipAddresses;

@end

NS_ASSUME_NONNULL_END
