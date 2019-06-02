//
//  MHHLSIOContext.h
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/11/30.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import <IJKMediaFramework/IJKMediaFramework.h>

@class MHResourceSet;

#define MH_LOCAL_PLAYER_NUMBER 0x9998

NS_ASSUME_NONNULL_BEGIN

@interface MHHLSIOContext : IJKHLSIOContext

/**
 * 设置新片源URL，如果片源未加载的话会自动去网络上加载片源信息
 * 新片源和旧片源的segment分割必须一致。
 */
- (void)swap:(NSURL *)url;

/**
 * 当前segment的duration
 */
- (NSTimeInterval)currentSegmentDuration;

@end

NS_ASSUME_NONNULL_END
