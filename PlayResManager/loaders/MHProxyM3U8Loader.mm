//
//  MHProxyM3U8Loader.m
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/10.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import "MHProxyM3U8Loader.h"
#import "../utils/utils.h"
#include "../utils/m3u8_parser.h"

const char proxy_compare_str[] = "#EXT-X-KEY";
const int proxy_compare_length = sizeof(proxy_compare_str) - 1;

@implementation MHProxyM3U8Loader

- (NSMutableData *)processData:(NSMutableData *)data {
    const char *chs = (const char *)data.bytes;
    const char *hostURL = "http://www.mh.com/";
    NSArray<IJKHLSSegment *>* segments = m3u8::parse_hls(chs, strlen(chs), hostURL);
    NSMutableData *newData = [NSMutableData data];
    const char header[] = "#EXTM3U\n"
    "#EXT-X-VERSION:3\n"
    "#EXT-X-ALLOW-CACHE:YES\n"
    "#EXT-X-TARGETDURATION:19\n"
    "#EXT-X-MEDIA-SEQUENCE:0\n";
    [newData appendBytes:header length:strlen(header)];
    for (IJKHLSSegment *seg in segments) {
        char str[256];
        sprintf(str, "#EXTINF:%f,\n", seg.duration / 1000000.0);
        [newData appendBytes:str length:strlen(str)];
        const char *path = seg.url.lastPathComponent.UTF8String;
        [newData appendBytes:path length:strlen(path)];
        [newData appendBytes:"\n" length:1];
    }
    
    const char tail[] = "#EXT-X-ENDLIST";
    [newData appendBytes:tail length:sizeof(tail)];
    
    return newData;
}

@end
