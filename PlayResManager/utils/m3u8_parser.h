//
//  m3u8_parser.h
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/6.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#ifndef m3u8_parser_h
#define m3u8_parser_h

#include <stdio.h>
#import <IJKMediaFramework/IJKMediaFramework.h>

namespace m3u8 {
    NSArray<IJKHLSSegment *>* parse_hls(const char *str, size_t size, const char *url);
}

#endif /* m3u8_parser_h */
