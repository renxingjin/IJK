//
//  MHPrivateM3U8Loader.h
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/6.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import "MHM3U8Loader.h"

NS_ASSUME_NONNULL_BEGIN

@interface MHPrivateM3U8Loader : MHM3U8Loader

+ (void)setKey:(NSString *)key forUrl:(NSString *)url;
+ (void)clearAllKeys;

@end

NS_ASSUME_NONNULL_END
