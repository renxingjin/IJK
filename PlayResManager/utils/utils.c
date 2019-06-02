//
//  utils.c
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/10.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#include "utils.h"

inline int mh_strcmp(const char *str1, const char *str2) {
    for (int i = 0, t = 256; i < t; ++i) {
        if (*(str1 + i) != *(str2 + i)) {
            return i;
        }
    }
    return 0;
}
