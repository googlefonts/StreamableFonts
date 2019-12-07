//
//  Seeds.h
//  Optimize
//
//  Created by Litherum on 12/7/19.
//  Copyright © 2019 Litherum. All rights reserved.
//

#pragma once

@import Foundation;

#import "GlyphData.h"

@interface Seeds : NSObject
- (instancetype)init;
- (instancetype)initWithGlyphData:(GlyphData *)glyphData andBigramScores:(NSData *)bigramScores;
@property (readonly) NSArray<NSArray<NSNumber *> *> *seeds;
+ (void)fillWithRandomSeeds:(NSMutableArray<NSArray<NSNumber *> *> *)array withGlyphCount:(NSUInteger)glyphCount untilCount:(NSUInteger)count;
@end
