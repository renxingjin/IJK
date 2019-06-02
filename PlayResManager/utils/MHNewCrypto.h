//
//  MHNewCrypto.h
//  PlayResManager
//
//  Created by Gen2 on 2019/2/22.
//  Copyright © 2019 Gen2. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MHNewCrypto : NSObject

@property (nonatomic, readonly) BOOL isCrypted;

- (id)initWithKey:(const char *)key index:(NSInteger)idx;

- (size_t)decrypt:(uint8_t *)data size:(size_t)size offset:(size_t)offset;

@end

NS_ASSUME_NONNULL_END
