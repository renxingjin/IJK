//
//  MHAESCrypto.m
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/3.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import "MHAESCrypto.h"
#include <CommonCrypto/CommonCrypto.h>
#include <vector>
#include "aes.hpp"

using namespace std;

#define AES_BLOCKLEN 16

@implementation MHAESCrypto {
    uint8_t _key[16];
    uint8_t _iv[16];
    struct AES_ctx _context;
}

- (id)initWithKey:(const uint8_t *)key iv:(const uint8_t *)iv {
    self = [super init];
    if (self) {
//        memcpy(_key, key, 16);
//        memcpy(_iv, iv, 16);
        AES_init_ctx_iv(&_context, key, iv);
    }
    return self;
}

- (size_t)decrypt:(uint8_t *)data size:(size_t)size {
//    size_t move;
//    CCCryptorStatus status = CCCrypt(kCCDecrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding, _key, 16, _iv, data, size, data, size, &move);
//    if (move != size) {
//        NSLog(@"GEN: move : %d - size: %d status %d", move, size, status);
//    }
//    return move;
    return (size_t)AES_CBC_decrypt_buffer(&_context, data, (uint32_t)size);
}

@end
