//
//  MHResourcesManager.h
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/11/30.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <IJKMediaFramework/IJKMediaFramework.h>

NS_ASSUME_NONNULL_BEGIN

#define MH_UNIT_KB 1024
#define MH_UNIT_MB (1024*1024)

@class MHResourcesManager;
@class MHResourceSet;
@class MHResourceItem;

typedef enum : NSUInteger {
    MHResourceItemNotStart,
    MHResourceItemLoading,
    MHResourceItemComplete,
    MHResourceItemFailed,
} MHResourceItemStatus;

typedef enum : NSUInteger {
    MHResourceSetIdle,
    MHResourceSetDownloading,
    MHResourceSetComplete,
    MHResourceSetFailed,
} MHResourceSetStatus;

typedef void (^MHResourceItemOnComplete)(NSError * _Nullable error);

@protocol MHResourceSetDelegate <NSObject>

- (void)resourceSet:(MHResourceSet *)resource itemComplete:(MHResourceItem *)item;
- (void)resourceSet:(MHResourceSet *)resource statusChanged:(MHResourceSetStatus)status;
- (void)resourceSet:(MHResourceSet *)resource speed:(NSUInteger)speed;
- (void)resourceSet:(MHResourceSet *)resource progress:(float)progress;

@end

/**
 * 播放道具(?),用于支持多播放器，比如播放器以及投屏，在数据层都被视作播放器。
 */
@interface MHResourcePlayItem : NSObject

@property (nonatomic, readonly, weak) MHResourceSet *resource;
@property (nonatomic, readonly) BOOL active;
@property (nonatomic, assign) NSUInteger preloadCount;
@property (nonatomic, readonly) NSUInteger cachedTo;
@property (nonatomic, assign) NSInteger playerNumber;

@property (nonatomic, readonly) BOOL isPaused;

/**
 * 需要播放某个资源，在start后才有效,当优先需要某个资源时使用
 * @param index 资源index
 */
- (int)requirePlay:(NSInteger)index;

/**
 * 停止播放, 在MHHLSIOContext中被使用
 */
- (void)exitPlaying;

/**
 * 暂停，在播放界面暂时离开，但是没有被释放的情况下使用，会暂停视频下载。
 * 避免在播放器未释放时与下载界面状态冲突。
 */
- (void)pause;

/**
 * 恢复，在播放界面回到前台时调用。
 */
- (void)resume;

@end

/**
 * @class MHResourceItem
 * 单个资源，即是.ts文件。
 *
 */
@interface MHResourceItem : NSObject

@property (atomic, readonly) MHResourceItemStatus status;
@property (nonatomic, readonly) IJKHLSSegment *segment;

/**
 * @property diskSize 硬盘空间， 未下载完成的时候是 0
 */
@property (nonatomic, readonly) NSUInteger diskSize;

@property (nonatomic, readonly) float progress;

- (id)initWithResource:(MHResourceSet *)resource segment:(IJKHLSSegment *)seg;

/**
 * @method readData:size:offset:
 * 不能在主线程调用，如果未下载完成会被挂起，直到状态转换，或者超时。
 *
 * @param buf       输出buffer
 * @param size      输出buffer size
 * @param offset    相对于item文件开头的偏移量
 * @return          写入长度
 */
- (int)readData:(uint8_t *)buf size:(int)size offset:(NSUInteger)offset;

/**
 * @method readAllData
 * 不能在主线程调用，如果未下载完成会被挂起，直到状态转换，或者超时。
 *
 * @return          data
 */
- (NSData *)readAllData;

- (void)start;
- (void)stop;

/**
 * @method clearCache
 * 删除缓存
 */
- (void)clearCache;

@end

/**
 * @class MHResourceSet
 * 资源集，用来表示一个m3u8文件及其资源
 *
 */
@interface MHResourceSet : NSObject

@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly) NSArray<MHResourceItem *> *items;
@property (nonatomic, weak, readonly) MHResourcesManager *manager;

/**
 * @property retryCount 失败重试次数
 *  连续失败多少次后，转换为失败状态。 default: 5
 */
@property (nonatomic, assign)   NSUInteger  retryCount;


/**
 * @property downloadSpeed 下载速度
 */
@property (nonatomic, readonly) NSUInteger downloadSpeed;

/**
 * @property diskSize
 * 占用硬盘空间
 */
@property (nonatomic, readonly) NSUInteger diskSize;

/**
 * @property completeCount
 * 完成的数目，可以用 m.items.count == 0 ? 0 : ((float)m.completeCount/m.items.count) 计算下载进度
 */
@property (nonatomic, readonly) NSUInteger completeCount;
@property (nonatomic, readonly) NSOperationQueue *queue;

@property (nonatomic, weak) id<MHResourceSetDelegate> delegate;

@property (nonatomic, readonly) float progress;

/**
 * @property status 当前资源集状态
 */
@property (nonatomic, readonly) MHResourceSetStatus status;

/**
 * 播放资源，在MHHLSIOContext中被使用
 * @param items 资源数据
 * @param start 是否开始下载
 */
- (MHResourcePlayItem *)playItems:(NSArray<MHResourceItem *> *)items start:(BOOL)start;

/**
 * 停止播放, 在MHHLSIOContext中被使用
 */
//- (void)exitPlaying;

/**
 * 在seek的时候调用可以立即停止所有请求, 可以让seek操作立即被响应
 * 直到播放器发出seek_complete消息
 * 但是，有时seek_complete可能延后，造成seek时间点不准确。
 */
- (void)onSeek;

- (MHResourcePlayItem *)getPlayItemWithNumber:(NSInteger)number;

@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) BOOL isDownloading;

/**
 * @method start
 * 开始下载 在下载界面使用
 * 与stop配对
 */
- (void)start;
/**
 * @method stop
 * 停止下载 在下载界面使用
 */
- (void)stop;

/**
 * @method loadAndStartFromUrl:
 * 从url下载资源
 * @param url           m3u8网络地址
 * @param loaderClass   m3u8载入loader,为空时将使用MHM3U8Loader
 * @param block         完成时block
 
 * TODO: 以url命名但是参数却是NSString
 */
- (void)loadItemsFromUrl:(NSString *)url
             loaderClass:(Class _Nullable)loaderClass
                   block:(void(^)(BOOL))block;
- (void)loadItemsFromUrl:(NSString *)url
                   block:(void(^)(BOOL))block;
/**
 * 从保存的数据中获取items信息
 * @return 是否成功读取
 */
- (BOOL)loadItemsFromDisk:(NSString *)url;

/**
 * @method clearCache
 * 删除缓存
 */
- (void)clearCache;

@end


@interface MHResourcesManager : NSObject

/**
 * @property bandwidthLimit 带宽限制, 0 既是不限制
 */
@property (nonatomic, assign) NSUInteger bandwidthLimit;
@property (nonatomic, assign) NSUInteger preloadCount;

+ (instancetype)instance;
/**
 * @method setup:
 * 初始化manager
 * @param path 缓存路径， 如果为空，将使用 "{NSCachesDirectory}/videos"
 */
- (void)setup:(NSString *)path;
/**
 * @method resourcesFromKey:
 * 获得一个资源集，推荐用url作为key
 *
 * @note 没有特殊情况的时候尽量使用 resourcesFromURL:
 */
- (MHResourceSet *)resourcesFromKey:(NSString *)key;
/**
 * @method resourcesFromURL:
 * 获得一个资源集，类似于resourcesFromKey: 不过针对带sign参数的优化处理
 * 会去除query参数
 * @param url  完整地址
 */
- (MHResourceSet *)resourcesFromURL:(NSURL *)url;

/**
 * 设置异或解码的Mask
 * @param maskkey 如:1542699431559
 * @param key 对应resourcesFromKey:中的key
 */
- (void)setMaskkey:(NSUInteger)maskkey forKey:(NSString *)key;
/**
 * 使用URL方案会无视query参数
 */
- (void)setMaskkey:(NSUInteger)maskkey forURL:(NSURL *)url;

- (void)clearAllMaskkeys;

/**
 * 设置aes解码的key
 * @param aeskey 如:#EXT-X-KEY:METHOD=AES-128,URI="gfyj.key",IV=0xe0f3152bb2ee9e5757255df637f1f99c
 * @param key 对应resourcesFromKey:中的key
 */
- (void)setAESkey:(NSString *)aeskey forKey:(NSString *)key;
/**
 * 使用URL方案会无视query参数
 */
- (void)setAESkey:(NSString *)aeskey forURL:(NSURL *)url;

- (void)clearAllAESkeys;

- (void)setCustomerHttpHeaders:(NSDictionary <NSString *, NSString *> *)headers;

/**
 * 清除缓存,建议在开始播放的时候清除
 * 清除后会发出 MHResourceManagerClearCacheNotification
 *     - object MHResourceManager
 *     - userInfo {MHResourceManagerKeepKey: 保留大小, MHResourceManagerDeleteKey: 被删除大小}
 * 
 * @param limitSize     限制
 * @param list      白名单，这些不会删除,不会被记入占用空间
 * @param url       希望的资源，这个资源一定会被保留
 */
- (void)clearCache:(NSUInteger)limitSize whiteList:(NSArray<NSURL *> * _Nullable)list wantUrl:(NSURL * _Nullable)url;

- (void)refreshNetwork;

- (void)showLogs;

@end

/**
 * 当m3u8地址，过期时被调用，object是NSURL类型的返回值。
 */
extern NSString * const MHResourceM3U8URLExpireNotification;

/**
 * 当某个片段请求失败时调用
 */
extern NSString * const MHResourceReadFailedNotification;

/**
 * 切换片源完成时的通知
 */
extern NSString * const MHResourceSwapNotification;

/**
 * 当清除缓存时被调用，可以获得保留大小和被删除大小
 */
extern NSString * const MHResourceManagerClearCacheNotification;
extern NSString * const MHResourceManagerKeepKey;
extern NSString * const MHResourceManagerDeleteKey;

NS_ASSUME_NONNULL_END
