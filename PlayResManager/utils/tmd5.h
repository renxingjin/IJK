//
//  md5.h
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/6.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#ifndef md5_h
#define md5_h

#include <CommonCrypto/CommonCrypto.h>

@class NSString;

#ifdef __cplusplus
extern "C" {
#endif
    NSString *md5String(NSString *input);
    NSString *c_md5String(NSString *input);
    NSString *c2_md5String(const char *buf, size_t len);
#ifdef __cplusplus
}
#endif

#endif /* md5_h */
