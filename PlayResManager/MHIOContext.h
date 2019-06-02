//
//  MHIOContext.h
//  IJKMediaDemo
//
//  Created by Gen2 on 2018/12/1.
//  Copyright © 2018年 bilibili. All rights reserved.
//

#import <IJKMediaFramework/IJKMediaFramework.h>

NS_ASSUME_NONNULL_BEGIN

@interface MHIOContext : IJKIOContext

/**
 * loader class
 * MHM3U8Loader 或其子类的class
 */
@property (nonatomic) Class loaderClass;

@end

NS_ASSUME_NONNULL_END
