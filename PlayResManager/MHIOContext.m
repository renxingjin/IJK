//
//  MHIOContext.m
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/1.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import "MHIOContext.h"
#import "MHResourcesManager.h"
#import "MHM3U8Loader.h"

@implementation MHIOContext {
    MHM3U8Loader    *_loader;
}

- (int)readPacket:(uint8_t *)buffer size:(int)size {
    return [_loader readData:buffer size:size];
}

- (int64_t)seek:(int64_t)off whence:(int)whence {
    return [_loader seek:off whence:whence];
}

- (BOOL)openFile:(NSString *)filename {
    NSURL *url = [NSURL URLWithString:filename];
    BOOL isM3u8 = [[url.pathExtension lowercaseString] isEqualToString:@"m3u8"];
    if (isM3u8) {
        MHResourceSet *resources = [[MHResourcesManager instance] resourcesFromURL:[NSURL URLWithString:filename]];
        if (!self.loaderClass) {
            self.loaderClass = MHM3U8Loader.class;
        }
        _loader = [[self.loaderClass alloc] initWithResources:resources
                                                        queue:resources.queue];
        [_loader open:filename];
    }
    return isM3u8;
}

@end
