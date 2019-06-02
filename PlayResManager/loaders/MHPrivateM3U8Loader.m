//
//  MHPrivateM3U8Loader.m
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/6.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import "MHPrivateM3U8Loader.h"
#import "MHResourcesManager.h"
#import "../utils/utils.h"

static NSMutableDictionary *_allKeys;

@implementation MHPrivateM3U8Loader

const char compare_str[] = "#EXT-X-DISCONTINUITY\n";
const int compare_length = sizeof(compare_str) - 1;

+ (void)setKey:(NSString *)key forUrl:(NSString *)url {
    if (!url) return;
    if (!_allKeys) {
        _allKeys = [NSMutableDictionary dictionary];
    }
    if (![key hasSuffix:@"\n"]) {
        key = [key stringByAppendingString:@"\n"];
    }
    MHResourceSet *r = [[MHResourcesManager instance] resourcesFromURL:[NSURL URLWithString:url]];
    [_allKeys setObject:key forKey:r.key];
}

- (NSMutableData *)processData:(NSMutableData *)data {
    NSString *key = [_allKeys objectForKey:self.resources.key];
    if (key) {
        const char *chs = data.bytes;
        for (NSUInteger i = 0, t = data.length; i < t; ++i) {
            if (mh_strcmp(chs + i, compare_str) == compare_length) {
                const char *c_key = key.UTF8String;
                [data replaceBytesInRange:NSMakeRange(i + compare_length, 0) withBytes:c_key length:strlen(c_key)];
                
                return data;
            }
        }
    }
    return data;
}

+ (void)clearAllKeys {
    [_allKeys removeAllObjects];
}

@end
