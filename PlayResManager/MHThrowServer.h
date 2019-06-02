//
//  MHThrowServer.h
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/16.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import <UIKit/UIKit.h>

@class MHRemotePlayer;
@class MHDLNAScaner;

typedef enum : NSUInteger {
    MHRemotePlayerPaused,
    MHRemotePlayerPlaying,
    MHRemotePlayerStoped,
} MHRemotePlayerState;

@interface MHDLNARenderer : NSObject

@property (nonatomic, readonly) NSString *friendlyName;
@property (nonatomic, readonly) NSString *smallestIcon;
@property (nonatomic, readonly) NSString *modelName;
@property (nonatomic, readonly) NSString *udn;

@end

@protocol MHDLNAScanerDelegate <NSObject>

- (void)dlnaScaner:(MHDLNAScaner *)scaner insertRenderer:(MHDLNARenderer *)renderer atIndex:(NSInteger)index;
- (void)dlnaScaner:(MHDLNAScaner *)scaner removeRenderer:(MHDLNARenderer *)renderer atIndex:(NSInteger)index;
- (void)dlnaScaner:(MHDLNAScaner *)scaner updateRenderer:(MHDLNARenderer *)renderer atIndex:(NSInteger)index;
- (void)dlnaScanerStop:(MHDLNAScaner *)scaner; //不一定停止，只是回调给页面停止动画

@end

@interface MHDLNAScaner : NSObject

@property (nonatomic, weak) id<MHDLNAScanerDelegate> delegate;

- (NSInteger)rendererCount;
- (MHDLNARenderer *)rendererAt:(NSInteger)index;

- (void)start;
- (void)scan;
- (void)stop;
- (void)research;

@end

@protocol MHRemotePlayerDelegate <NSObject>

- (void)player:(MHRemotePlayer *)player stateChanged:(MHRemotePlayerState)state;

@end

@interface MHRemotePlayer : NSObject

@property (nonatomic, readonly) MHRemotePlayerState state;
@property (nonatomic, weak) id<MHRemotePlayerDelegate> delegate;

- (void)playCallback:(dispatch_block_t)callback;
- (void)pauseCallback:(dispatch_block_t)callback;

- (NSTimeInterval)duration;
- (void)seek:(NSTimeInterval)time;
- (NSTimeInterval)currentTime;

- (void)start;
- (void)close;

- (BOOL)isPlaying;

@property (nonatomic, assign) NSInteger volume;

@end

@interface MHAirplayPlayer : MHRemotePlayer

@property (nonatomic, strong) UIView *view;

@end

@interface MHDLNAPlayer : MHRemotePlayer

@property (nonatomic, strong) MHDLNARenderer *renderer;

@end

@interface MHThrowServer : NSObject

@property (nonatomic, strong) MHRemotePlayer *player;
@property (nonatomic, strong) NSString *url;

@property (nonatomic, assign) BOOL isLocalServer;

- (void)start;
- (void)stop;
- (void)swap:(NSString *)url;

@end
