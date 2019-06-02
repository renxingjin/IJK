//
//  MHM3U8Loader.h
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/6.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MHResourceSet;
@class IJKHLSSegment;

NS_ASSUME_NONNULL_BEGIN

typedef BOOL(^MHPlaylistValidater)(NSArray<IJKHLSSegment *>* playlist);

@interface MHM3U8Loader : NSObject

@property (nonatomic, readonly) MHResourceSet *resources;

- (void)cancel;

- (id)initWithResources:(MHResourceSet *)resources queue:(NSOperationQueue *)queue;

- (void)open:(NSString *)url;
- (int)readLine:(char *)buf size:(size_t)size;
- (int)readData:(char *)buf size:(size_t)size;
- (NSData *)loadAll;
- (NSUInteger)seek:(NSUInteger)offset whence:(int)whence;

+ (void)setPlaylistValidate:(MHPlaylistValidater)validater;

/**
 * @method processData:
 * overide this method to process data.
 */
- (NSMutableData *)processData:(NSMutableData *)data;

@end

NS_ASSUME_NONNULL_END
