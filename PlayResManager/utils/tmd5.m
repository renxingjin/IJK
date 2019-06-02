//
//  tmd5.c
//  PlayResManager
//
//  Created by Gen2 on 2019/2/28.
//  Copyright © 2019 Gen2. All rights reserved.
//

#include "tmd5.h"
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
    NSString *md5String(NSString *input) {
        if (!input) {
            return NULL;
        }
        unsigned char result[CC_MD5_DIGEST_LENGTH];
        NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
        CC_MD5(data.bytes, (CC_LONG)data.length, result);
        NSString *ret = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                         result[0],result[1],result[2],result[3],result[4],result[5],result[6],result[7],result[8],result[9],result[10],result[11],result[12],result[13],result[14],result[15]];
        
        return ret;
    }
    
    
    NSString *c_md5String(NSString *input) {
        if (!input) {
            return NULL;
        }
        unsigned char result[CC_MD5_DIGEST_LENGTH];
        char MD5_tmp_str[32];
        NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
        CC_MD5(data.bytes, (CC_LONG)data.length, result);
        NSString *ret = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                         result[0],result[1],result[2],result[3],result[4],result[5],result[6],result[7],result[8],result[9],result[10],result[11],result[12],result[13],result[14],result[15]];
        
        return ret;
    }
    NSString *c2_md5String(const char *buf, size_t len) {
        unsigned char result[CC_MD5_DIGEST_LENGTH];
        CC_MD5(buf, (CC_LONG)len, result);
        char MD5_tmp_str[32];
        NSString *ret = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                         result[0],result[1],result[2],result[3],result[4],result[5],result[6],result[7],result[8],result[9],result[10],result[11],result[12],result[13],result[14],result[15]];
        
        return ret;
    }
#ifdef __cplusplus
}
#endif

