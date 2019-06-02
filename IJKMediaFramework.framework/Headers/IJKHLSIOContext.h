//
//  IJKIOContext.h
//  IJKMediaFramework
//
//  Created by Gen2 on 2018/11/30.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

struct av_hls_segment;

typedef enum : NSUInteger {
    IJKHLSSegmentNone,
    IJKHLSSegmentAES128,
    IJKHLSSegmentSampleAES,
} IJKHLSSegmentType;

@interface IJKHLSSegment : NSObject

- (id)initWithSegment:(struct av_hls_segment *)segment;

@property (nonatomic, assign) NSUInteger duration;
@property (nonatomic, assign) NSUInteger urlOffset;
@property (nonatomic, assign) NSUInteger size;
@property (nonatomic, strong) NSString *url;
@property (nonatomic, strong) NSString *key;
@property (nonatomic, assign) IJKHLSSegmentType type;
@property (nonatomic, assign) NSInteger secretKeyIndex;
@property (nonatomic, strong) NSString  *secretKey;

// iv size 16
- (uint8_t*)iv;
- (void)set_iv:(uint8_t*)iv;

@end

@interface IJKHLSIOContext : NSObject

- (void)onParsedPlaylist:(NSArray <IJKHLSSegment *> *)sgements url:(NSString *)url;
- (int)openSegmentAt:(NSUInteger)index;
- (int)readData:(uint8_t *)buf size:(int)size offset:(NSUInteger)offset;
- (void)onShutdown;

@end

NS_ASSUME_NONNULL_END
