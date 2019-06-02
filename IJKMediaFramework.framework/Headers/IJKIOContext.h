//
//  IJKIOContext.h
//  IJKMediaFramework
//
//  Created by Gen2 on 2018/12/1.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IJKIOContext : NSObject

- (int)readPacket:(uint8_t *)buffer size:(int)size;
- (int64_t)seek:(int64_t)off whence:(int)whence;
- (BOOL)openFile:(NSString *)filename;

@end

NS_ASSUME_NONNULL_END
