//
//  MHThrowServer.m
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/16.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import "MHThrowServer.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CLUPnP/CLUPnP.h>
#import "MHLocalServer.h"
#import "MHResourcesManager.h"

@interface MHDLNARenderer () {
    CLUPnPDevice *_device;
    CLUPnPRenderer  *_renderer;
}

@property (nonatomic, readonly) CLUPnPRenderer *avRenderer;

- (id)initWithDevice:(CLUPnPDevice *)device;

@end

@implementation MHDLNARenderer

- (id)initWithDevice:(CLUPnPDevice *)device {
    self = [self init];
    if (self) {
        _device = device;
    }
    return self;
}

- (NSString *)friendlyName {
    return _device.friendlyName;
}

- (NSString *)smallestIcon {
    return nil;
}
- (NSString *)modelName {
    return _device.modelName;
}
- (NSString *)udn {
    return _device.uuid;
}

- (CLUPnPRenderer *)avRenderer {
    if (!_renderer && _device) {
        _renderer = [[CLUPnPRenderer alloc] initWithModel:_device];
    }
    return _renderer;
}

@end

@interface MHDLNAScaner() <CLUPnPServerDelegate>

@property (nonatomic, strong) NSMutableArray * renderers;

@end

@implementation MHDLNAScaner {
    NSMutableDictionary *_renderersIndex;
    CLUPnPServer  *_server;
    
    dispatch_queue_t _queue;
}

- (NSInteger)rendererCount {
    @synchronized (_renderers) {
        return _renderers.count;
    }
}

- (MHDLNARenderer *)rendererAt:(NSInteger)index {
    @synchronized (_renderers) {
        if (_renderers.count > index && index >= 0) {
            return [_renderers objectAtIndex:index];
        }
    }
    return nil;
}

- (id)init {
    self = [super init];
    if (self) {
        _renderersIndex = [NSMutableDictionary dictionary];
        _renderers = [NSMutableArray array];
        
        _server = [CLUPnPServer shareServer];
        _server.delegate = self;
        _queue = dispatch_queue_create("MHDLNAScaner", NULL);
    }
    return self;
}


- (void)upnpSearchChangeWithResults:(NSArray<CLUPnPDevice *> *)devices{
    NSLog(@"发现设备");
    NSMutableSet *keys = [NSMutableSet set];
    for (CLUPnPDevice *dev in devices) {
        [keys addObject:dev.uuid];
        if ([_renderersIndex objectForKey:dev.uuid]) {
            if ([self.delegate respondsToSelector:@selector(dlnaScanerStop:)]) {
                [self.delegate dlnaScanerStop:self];
            }
        }else {
            MHDLNARenderer *renderer = [[MHDLNARenderer alloc] initWithDevice:dev];
            [_renderersIndex setObject:renderer forKey:dev.uuid];
            [_renderers addObject:renderer];
            
            if ([self.delegate respondsToSelector:@selector(dlnaScaner:insertRenderer:atIndex:)]) {
                NSInteger idx = _renderers.count - 1;
                [self.delegate dlnaScaner:self
                           insertRenderer:renderer
                                  atIndex:idx];
            }
        }
    }
    
//    for (NSInteger i = 0, t = _renderers.count; i < t; ++i) {
//        MHDLNARenderer *renderer = [_renderers objectAtIndex:i];
//        if (![keys containsObject:renderer.udn]) {
//            [_renderers removeObjectAtIndex:i];
//            if (i >= 0 && [self.delegate respondsToSelector:@selector(dlnaScaner:removeRenderer:atIndex:)]) {
//                [self.delegate dlnaScaner:self
//                           removeRenderer:renderer
//                                  atIndex:i];
//            }
//            --i;
//            --t;
//        }
//    }
}

- (void)start {
    [_server start];
}
- (void)scan {
    [_server search];
}
- (void)stop {
    [_server stop];
}
- (void)research {
    [_server search];
}

@end

@interface MHRemotePlayer() {
@protected
    MHRemotePlayerState _state;
}

@property (nonatomic, strong) NSString *url;
- (void)stateChanged;

- (void)setDuration:(NSTimeInterval)duration;

@end

@implementation MHRemotePlayer

@dynamic volume;
@synthesize state = _state;

- (void)playCallback:(dispatch_block_t)callback {
    
}

- (void)pauseCallback:(dispatch_block_t)callback {
    
}

- (void)setDuration:(NSTimeInterval)duration {
    
}

- (NSTimeInterval)duration {
    return 0;
}

- (void)seek:(NSTimeInterval)time {
    
}

- (NSTimeInterval)currentTime {
    return 0;
}

- (void)start {
    
}
- (void)close {
    
}

- (BOOL)isPlaying {
    return NO;
}

- (void) stateChanged {
    [self performSelectorOnMainThread:@selector(stateChangedMainThread)
                           withObject:nil
                        waitUntilDone:NO];
}

- (void)stateChangedMainThread {
    if ([self.delegate respondsToSelector:@selector(player:stateChanged:)]) {
        [self.delegate player:self stateChanged:_state];
    }
}

@end

@implementation MHAirplayPlayer {
    AVPlayer *_player;
    AVPlayerLayer *_playerLayer;
}

- (void)start {
    if (!self.url) {
        @throw @"No url seted!";
    }
    if (!self.view) {
        @throw @"No view seted!";
    }
    if (_player) {
        [_player pause];
        _player = nil;
    }
    if (_playerLayer) {
        [_playerLayer removeFromSuperlayer];
        _playerLayer = nil;
    }
    
    
    AVAsset *asset = [AVAsset assetWithURL:[NSURL URLWithString:self.url]];
    AVPlayerItem *item = [[AVPlayerItem alloc] initWithAsset:asset];
    _player = [[AVPlayer alloc] initWithPlayerItem:item];
    
    [_player addObserver:self
              forKeyPath:@"timeControlStatus"
                 options:NSKeyValueObservingOptionNew
                 context:nil];
    _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
    _playerLayer.frame = CGRectMake(0, 0, 120, 90);
    [self.view.layer addSublayer:_playerLayer];
    [_player play];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"timeControlStatus"]) {
        AVPlayerTimeControlStatus status = [[change objectForKey:NSKeyValueChangeNewKey] integerValue];
        switch (status) {
            case AVPlayerTimeControlStatusPaused:
                if (_state != MHRemotePlayerPaused) {
                    _state = MHRemotePlayerPaused;
                    [self stateChanged];
                }
                break;
            case AVPlayerTimeControlStatusPlaying:
                if (_state != MHRemotePlayerStoped) {
                    _state = MHRemotePlayerStoped;
                    [self stateChanged];
                }
                break;
                
            default:
                break;
        }
    }
}

- (void)close {
    [_player pause];
    [_playerLayer removeFromSuperlayer];
    _playerLayer = nil;
    _player = nil;
}

- (void)playCallback:(dispatch_block_t)callback {
    [_player play];
}

- (void)pauseCallback:(dispatch_block_t)callback {
    [_player pause];
}

- (BOOL)isPlaying {
    return _player.timeControlStatus == AVPlayerTimeControlStatusPlaying;
}

- (NSTimeInterval)duration {
    return CMTimeGetSeconds(_player.currentItem.duration);
}

- (void)seek:(NSTimeInterval)time {
    [_player seekToTime:CMTimeMake(time * 1000, 1000)];
}

- (NSTimeInterval)currentTime {
    return CMTimeGetSeconds(_player.currentTime);
}

- (void)setVolume:(NSInteger)volume {
    [_player setVolume:volume/100.0];
}

- (NSInteger)volume {
    return _player.volume * 100;
}

@end

@implementation MHDLNAPlayer {
    dispatch_queue_t _task_queue;
    
    NSTimeInterval _duration;
    NSTimeInterval _currentTime;
    NSTimeInterval _currentRealTime;
    
    BOOL _isRunning;
}

- (void)start {
    if (!self.url) {
        @throw @"No url seted!";
    }
    if (!self.renderer) {
        @throw @"No view seted!";
    }
    
    _isRunning = YES;
    
    _task_queue = dispatch_queue_create("MHDLNAPlayer", NULL);
    dispatch_async(_task_queue, ^{
        if ([self.renderer.avRenderer setAVTransportURL:self.url]) {
            [self.renderer.avRenderer play];
            self->_state = MHRemotePlayerPlaying;
            [self stateChanged];
            self->_currentTime = 0;
            self->_currentRealTime = [NSDate date].timeIntervalSince1970;
            
            [self getPosition];
        };
    });
}

- (void)getPosition {
    dispatch_async(_task_queue, ^{
        CLUPnPAVPositionInfo *pos = [self.renderer.avRenderer getPositionInfo];
        @synchronized (self) {
            self->_currentTime = pos.relTime;//pos.absTime;
            self->_currentRealTime = [NSDate date].timeIntervalSince1970;
            if (pos.trackDuration > 0)
                self->_duration = pos.trackDuration;
        }
        CLUPnPTransportInfo *trans = [self.renderer.avRenderer getTransportInfo];
        BOOL changed = NO;
        @synchronized (self) {
            if ([trans.currentTransportState isEqualToString:@"PLAYING"]) {
                if (self->_state != MHRemotePlayerPlaying) {
                    self->_state = MHRemotePlayerPlaying;
                    changed = YES;
                }
            }else if ([trans.currentTransportState isEqualToString:@"STOPPED"]) {
                if (self->_state != MHRemotePlayerStoped) {
                    self->_state = MHRemotePlayerStoped;
                }
                changed = YES;
            }else if ([trans.currentTransportState isEqualToString:@"PAUSED_PLAYBACK"]) {
                if (self->_state != MHRemotePlayerPaused) {
                    self->_state = MHRemotePlayerPaused;
                    changed = YES;
                }
            }
        }
        if (changed) {
            [self stateChanged];
        }
        
        if (self->_isRunning) {
            [self performSelectorOnMainThread:@selector(getPositionDelay)
                       withObject:nil
                       waitUntilDone:NO];
        }
    });
}

- (void)getPositionDelay {
    [self performSelector:@selector(getPosition)
                           withObject:nil
                        afterDelay:5];
}

- (void)close {
    _isRunning = NO;
    _currentTime = 0;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    dispatch_async(_task_queue, ^{
        [self.renderer.avRenderer stop];
    });
}

- (void)playCallback:(dispatch_block_t)callback {
    dispatch_async(_task_queue, ^{
        CLUPnPResponse *response = [self.renderer.avRenderer play];
        @synchronized (self) {
            if ([response.name isEqualToString:@"PlayResponse"]) {
                if (self->_state != MHRemotePlayerPlaying) {
                    self->_state = MHRemotePlayerPlaying;
                }
            }
            if (callback) {
                callback();
            }
        }
    });
}

- (void)pauseCallback:(dispatch_block_t)callback {
    dispatch_async(_task_queue, ^{
        CLUPnPResponse *response = [self.renderer.avRenderer pause];
        @synchronized (self) {
            if ([response.name isEqualToString:@"PauseResponse"]) {
                if (self->_state != MHRemotePlayerPaused) {
                    self->_state = MHRemotePlayerPaused;
                }
            }
            if (callback) {
                callback();
            }
        }
    });
}

- (BOOL)isPlaying {
    return _state == MHRemotePlayerPlaying;
}

- (NSTimeInterval)duration {
    @synchronized (self) {
        return _duration;
    }
}

- (void)setDuration:(NSTimeInterval)duration {
    @synchronized (self) {
        _duration = duration;
    }
}

- (void)seek:(NSTimeInterval)time {
    dispatch_async(_task_queue, ^{
        self->_currentTime = time;
//        self->_state = MHRemotePlayerPlaying;
        [self.renderer.avRenderer seek:time];
    });
}

- (NSTimeInterval)currentTime {
    @synchronized (self) {
        return _currentTime;//_currentTime + (self.isPlaying ? ([NSDate date].timeIntervalSince1970 - _currentRealTime) : 0);
    }
}

- (NSInteger)volume {
    return [self.renderer.avRenderer.getVolume integerValue];
}

- (void)setVolume:(NSInteger)volume {
    dispatch_async(_task_queue, ^{
        [self.renderer.avRenderer setVolumeWith:[NSString stringWithFormat:@"%d", (int)volume]];
    });
}

@end

@interface MHThrowServer() <GCDWebServerDelegate>

@end

@implementation MHThrowServer {
    MHLocalServer   *_localServer;
    MHServerItem    *_serverItem;
    NSTimeInterval  _currentPos;
}

- (id)init {
    self = [super init];
    if (self) {
        _isLocalServer = YES;
    }
    return self;
}

- (void)start {
    _currentPos = 0;
    if (self.isLocalServer) {
        if (!_localServer) {
            _localServer = [[MHLocalServer alloc] init];
            _localServer.delegate = self;
        }
        _serverItem = [[MHServerItem alloc] initWithURL:[NSURL URLWithString:_url]];
        [_localServer startItem:_serverItem block:nil];
    }else {
        self.player.url = self.url;
        [self.player start];
    }
}

- (void)stop {
    if (self.isLocalServer) {
        [_localServer stopItem:_serverItem];
    }
    [self.player close];
}

- (void)swap:(NSString *)url {
    if (self.isLocalServer) {
        [_localServer stopItem:_serverItem];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_url = url;
        if (self.isLocalServer) {
            if (!self->_localServer) {
                self->_localServer = [[MHLocalServer alloc] init];
                self->_localServer.delegate = self;
            }
            self->_serverItem = [[MHServerItem alloc] initWithURL:[NSURL URLWithString:self->_url]];
            [self->_localServer startItem:self->_serverItem block:nil];
        }else {
            self.player.url = self.url;
            [self.player start];
        }
    });
}

- (void)setIsLocalServer:(BOOL)isLocalServer {
    if (_isLocalServer != isLocalServer) {
        _isLocalServer = isLocalServer;
        _currentPos = self.player.currentTime;
        if (_isLocalServer) {
            if (!_localServer) {
                _localServer = [[MHLocalServer alloc] init];
                _localServer.delegate = self;
            }
            _serverItem = [[MHServerItem alloc] initWithURL:[NSURL URLWithString:_url]];
            [_localServer startItem:_serverItem block:^(NSArray * items) {
                NSTimeInterval duration = 0;
                for (MHResourceItem *item in items) {
                    duration += item.segment.duration;
                }
                [self.player setDuration:duration];
            }];
        }else {
            self.player.url = self.url;
            [self.player playCallback:nil];
            [self.player seek:_currentPos];
        }
    }
}

- (void)webServerDidStart:(GCDWebServer*)server {
    NSString *host = [[MHLocalServer ipAddresses] firstObject];
    if (server.port != 80) {
        host = [host stringByAppendingFormat:@":%d", (int)server.port];
    }
    self.player.url = [NSString stringWithFormat:@"http://%@/%@/%@", host, _serverItem.md5, [_serverItem.url lastPathComponent]];
    [self.player start];
    if (_currentPos != 0) {
        [self.player seek:_currentPos];
    }
}

@end
