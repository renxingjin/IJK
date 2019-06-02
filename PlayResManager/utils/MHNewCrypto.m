//
//  MHNewCrypto.m
//  PlayResManager
//
//  Created by Gen2 on 2019/2/22.
//  Copyright © 2019 Gen2. All rights reserved.
//

#import "MHNewCrypto.h"
#import "bcrypto_internal.h"

@implementation MHNewCrypto {
    ngx_vod_jack_key_data_s jack_key;
}

- (id)initWithKey:(const char *)key index:(NSInteger)idx {
    self = [super init];
    if (self) {
        if (decode_bcrypto_key(key, &jack_key, (int32_t)idx) != 0) {
            return nil;
        }
    }
    return self;
}

- (BOOL)isCrypted {
    return jack_key.cryptMethod;
}

- (size_t)decrypt:(uint8_t *)data size:(size_t)size offset:(size_t)offset {
    return (size_t)decode_bcrypto_buf(data, (uint32_t)size, &data, &jack_key, (int32_t)offset);
}

@end
