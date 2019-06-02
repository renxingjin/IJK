//
//  MHHLSIOContext.m
//  IJKMediaDemo`
//
//  Created by Gen2 on 2018/11/30.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import "MHHLSIOContext.h"
#import "MHResourcesManager.h"


@interface MHHLSIOContext ()

@property (nonatomic, strong, nullable) MHResourceSet *swapResource;

@end

@implementation MHHLSIOContext {
    MHResourceItem      *_currentItem;
    MHResourcePlayItem  *_playItem;
}


- (void)onParsedPlaylist:(NSArray <IJKHLSSegment *> *)segments url:(NSString *)url {
    if (_playItem) {
        [_playItem exitPlaying];
    }
    
    
    MHResourceSet *resources = [[MHResourcesManager instance] resourcesFromURL:[NSURL URLWithString:url]];
    NSMutableArray *_tasks = [NSMutableArray arrayWithCapacity:segments.count];
    for (IJKHLSSegment *seg in segments) {
        MHResourceItem *item = [[MHResourceItem alloc] initWithResource:resources
                                                                segment:seg];
        [_tasks addObject:item];
    }
    _playItem = [resources playItems:_tasks start:YES];
    _playItem.playerNumber = MH_LOCAL_PLAYER_NUMBER;
}

- (int)openSegmentAt:(NSUInteger)index {
    if (self.swapResource) {
        if (self.swapResource.items) {
            [_playItem exitPlaying];
            MHResourceSet *resources = self.swapResource;
            _playItem = [resources playItems:resources.items
                                       start:YES];
            self.swapResource = nil;
            [[NSNotificationCenter defaultCenter] postNotificationName:MHResourceSwapNotification
                                                                object:resources];
        }else {
//            NSLog(@"Error : please load resource items first");
        }
    }
    if (index < _playItem.resource.items.count) {
        _currentItem = [_playItem.resource.items objectAtIndex:index];
        return [_playItem requirePlay:index];
    }else {
        _currentItem = nil;
        return -1;
    }
    return 0;
}

- (int)readData:(uint8_t *)buf size:(int)size offset:(NSUInteger)offset {
    if (_currentItem) {
        return [_currentItem readData:buf size:size offset:offset];
    }
    return 0;
}
//
//- (NSUInteger)onSeek:(NSUInteger)offset mode:(int)mode {
//    return offset;
//}
//
//- (void)closeCurrentSegment {
//    [_currentItem stop];
//    _currentItem = nil;
//}

- (void)onShutdown {
    [_playItem exitPlaying];
}

- (NSTimeInterval)currentSegmentDuration {
    return _currentItem.segment.duration / 1000.0 / 1000.0;
}

- (void)swap:(NSURL *)url {
    MHResourceSet *set = [[MHResourcesManager instance] resourcesFromURL:url];
    if (!set.items) {
        __weak MHHLSIOContext *this = self;
        [set loadItemsFromUrl:url.absoluteString
                        block:^(BOOL ret) {
                            if (ret) {
                                this.swapResource = set;
                            }else {
                                NSLog(@"Error : failed to load %@", url);
                                [[NSNotificationCenter defaultCenter] postNotificationName:MHResourceSwapNotification
                                                                                    object:nil];
                            }
                        }];
    }else {
        self.swapResource = set;
    }
}

@end
