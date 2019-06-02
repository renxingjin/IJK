//
//  MHAESCrypto.h
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/3.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MHAESCrypto : NSObject

- (id)initWithKey:(const uint8_t *)key iv:(const uint8_t *)iv;

- (size_t)decrypt:(uint8_t *)data size:(size_t)size;

@end

NS_ASSUME_NONNULL_END
