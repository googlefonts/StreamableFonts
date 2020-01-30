//
//  SimulatedAnnealing.m
//  Optimize
//
//  Created by Myles C. Maxfield on 1/30/20.
//  Copyright © 2020 Litherum. All rights reserved.
//

#import "SimulatedAnnealing.h"

@import Metal;

#import <assert.h>

@implementation SimulatedAnnealing {
    GlyphData *glyphData;
    NSArray<NSArray<NSNumber *> *> *seeds;

    uint32_t glyphCount;
    uint32_t glyphBitfieldSize;
    uint32_t urlCount;
    uint32_t generationSize;
    BOOL state;

    id<MTLDevice> device;
    id<MTLCommandQueue> queue;

    id<MTLFunction> fitnessFunction;
    id<MTLFunction> sumFitnessesFunction;
    id<MTLFunction> swapGlyphsFunction;
    id<MTLFunction> annealFunction;
    id<MTLComputePipelineState> fitnessState;
    id<MTLComputePipelineState> sumFitnessesState;
    id<MTLComputePipelineState> swapGlyphsState;
    id<MTLComputePipelineState> annealState;
    id<MTLBuffer> generationBuffer;
    id<MTLBuffer> glyphSizesBuffer;
    id<MTLBuffer> urlBitmapsBuffer;
    id<MTLBuffer> fitnessesPerURLBuffer;
    id<MTLBuffer> fitnessABuffer;
    id<MTLBuffer> fitnessBBuffer;
}

- (instancetype)initWithGlyphData:(GlyphData *)glyphData andSeeds:(NSArray<NSArray<NSNumber *> *> *)seeds
{
    self = [super init];

    if (self) {
        self->glyphData = glyphData;
        self->seeds = seeds;
        
        glyphCount = (uint32_t)glyphData.glyphCount;
        glyphBitfieldSize = (uint32_t)glyphData.glyphBitfieldSize;
        urlCount = (uint32_t)glyphData.urlCount;
        generationSize = (uint32_t)seeds.count;
        state = NO;

        device = MTLCreateSystemDefaultDevice();
        queue = [device newCommandQueue];

        [self loadShaders];
        [self createMetalStates];
        [self createBuffers];
    }

    return self;
}

- (void)loadShaders
{
    NSError *error = nil;
    NSBundle *bundle = [NSBundle bundleForClass:[SimulatedAnnealing class]];
    id<MTLLibrary> library = [device newDefaultLibraryWithBundle:bundle error:&error];
    assert(error == nil);
    MTLFunctionConstantValues *constantValues = [MTLFunctionConstantValues new];
    [constantValues setConstantValue:&glyphCount type:MTLDataTypeUInt withName:@"glyphCount"];
    [constantValues setConstantValue:&glyphBitfieldSize type:MTLDataTypeUInt withName:@"glyphBitfieldSize"];
    [constantValues setConstantValue:&urlCount type:MTLDataTypeUInt withName:@"urlCount"];
    fitnessFunction = [library newFunctionWithName:@"fitness" constantValues:constantValues error:&error];
    assert(error == nil);
    sumFitnessesFunction = [library newFunctionWithName:@"sumFitnesses" constantValues:constantValues error:&error];
    assert(error == nil);
    swapGlyphsFunction = [library newFunctionWithName:@"swapGlyphs" constantValues:constantValues error:&error];
    assert(error == nil);
    swapGlyphsFunction = [library newFunctionWithName:@"anneal" constantValues:constantValues error:&error];
    assert(error == nil);
}

- (void)createMetalStates
{
    NSError *error;
    {
        MTLComputePipelineDescriptor *fitnessPiplineDescriptor = [MTLComputePipelineDescriptor new];
        fitnessPiplineDescriptor.computeFunction = fitnessFunction;
        fitnessPiplineDescriptor.buffers[0].mutability = MTLMutabilityImmutable;
        fitnessPiplineDescriptor.buffers[1].mutability = MTLMutabilityImmutable;
        fitnessPiplineDescriptor.buffers[2].mutability = MTLMutabilityImmutable;
        fitnessPiplineDescriptor.buffers[3].mutability = MTLMutabilityMutable;
        fitnessState = [device newComputePipelineStateWithDescriptor:fitnessPiplineDescriptor options:MTLPipelineOptionNone reflection:nil error:&error];
        assert(error == nil);
    }

    {
        MTLComputePipelineDescriptor *sumFitnessesPiplineDescriptor = [MTLComputePipelineDescriptor new];
        sumFitnessesPiplineDescriptor.computeFunction = sumFitnessesFunction;
        sumFitnessesPiplineDescriptor.buffers[0].mutability = MTLMutabilityImmutable;
        sumFitnessesPiplineDescriptor.buffers[1].mutability = MTLMutabilityMutable;
        sumFitnessesState = [device newComputePipelineStateWithDescriptor:sumFitnessesPiplineDescriptor options:MTLPipelineOptionNone reflection:nil error:&error];
        assert(error == nil);
    }

    {
        MTLComputePipelineDescriptor *swapGlyphsPiplineDescriptor = [MTLComputePipelineDescriptor new];
        swapGlyphsPiplineDescriptor.computeFunction = swapGlyphsFunction;
        swapGlyphsPiplineDescriptor.buffers[0].mutability = MTLMutabilityMutable;
        swapGlyphsPiplineDescriptor.buffers[1].mutability = MTLMutabilityImmutable;
        swapGlyphsState = [device newComputePipelineStateWithDescriptor:swapGlyphsPiplineDescriptor options:MTLPipelineOptionNone reflection:nil error:&error];
        assert(error == nil);
    }

    {
        MTLComputePipelineDescriptor *annealPiplineDescriptor = [MTLComputePipelineDescriptor new];
        annealPiplineDescriptor.computeFunction = annealFunction;
        annealPiplineDescriptor.buffers[0].mutability = MTLMutabilityMutable;
        annealPiplineDescriptor.buffers[1].mutability = MTLMutabilityImmutable;
        annealPiplineDescriptor.buffers[2].mutability = MTLMutabilityImmutable;
        annealPiplineDescriptor.buffers[3].mutability = MTLMutabilityMutable;
        annealPiplineDescriptor.buffers[4].mutability = MTLMutabilityImmutable;
        annealState = [device newComputePipelineStateWithDescriptor:annealPiplineDescriptor options:MTLPipelineOptionNone reflection:nil error:&error];
        assert(error == nil);
    }
}

- (void)createBuffers
{
    uint32_t seedsData[generationSize * glyphCount];
    assert(seeds.count == generationSize);
    for (uint32_t i = 0; i < generationSize; ++i) {
        NSArray<NSNumber *> *seed = seeds[i];
        assert(seed.count == glyphCount);
        for (uint32_t j = 0; j < glyphCount; ++j)
            seedsData[glyphCount * i + j] = seed[j].unsignedIntValue;
    }
    generationBuffer = [device newBufferWithBytes:seedsData length:glyphCount * generationSize * sizeof(uint32_t) options:MTLResourceStorageModeManaged];

    uint32_t glyphSizesData[glyphCount];
    for (uint32_t i = 0; i < glyphCount; ++i)
        glyphSizesData[i] = glyphData.glyphSizes[i].unsignedIntValue;
    glyphSizesBuffer = [device newBufferWithBytes:glyphSizesData length:glyphCount * sizeof(uint32_t) options:MTLResourceStorageModeManaged];

    urlBitmapsBuffer = [device newBufferWithBytes:glyphData.urlBitmaps length:urlCount * glyphBitfieldSize * sizeof(uint8_t) options:MTLResourceStorageModeManaged];

    fitnessesPerURLBuffer = [device newBufferWithLength:generationSize * urlCount * sizeof(uint32_t) options:MTLResourceStorageModeManaged];
    fitnessABuffer = [device newBufferWithLength:generationSize * sizeof(uint32_t) options:MTLResourceStorageModeManaged];
    fitnessBBuffer = [device newBufferWithLength:generationSize * sizeof(uint32_t) options:MTLResourceStorageModeManaged];
}

- (void)computeFitnessesWithComputeCommandEncoder:(id<MTLComputeCommandEncoder>)computeCommandEncoder andFitnessBuffer:(id<MTLBuffer>)fitnessBuffer
{
    {
        [computeCommandEncoder setComputePipelineState:fitnessState];
        id<MTLBuffer> buffers[] = {generationBuffer, glyphSizesBuffer, urlBitmapsBuffer, fitnessesPerURLBuffer};
        NSUInteger offsets[] = {0, 0, 0, 0};
        [computeCommandEncoder setBuffers:buffers offsets:offsets withRange:NSMakeRange(0, 4)];
        [computeCommandEncoder dispatchThreads:MTLSizeMake(generationSize, urlCount, 1) threadsPerThreadgroup:MTLSizeMake(32, 32, 1)];
    }
    {
        [computeCommandEncoder setComputePipelineState:sumFitnessesState];
        id<MTLBuffer> buffers[] = {fitnessesPerURLBuffer, fitnessBuffer};
        NSUInteger offsets[] = {0, 0};
        [computeCommandEncoder setBuffers:buffers offsets:offsets withRange:NSMakeRange(0, 2)];
        [computeCommandEncoder dispatchThreads:MTLSizeMake(generationSize, 1, 1) threadsPerThreadgroup:MTLSizeMake(512, 1, 1)];
    }
}

- (void)swapGlyphsWithComputeCommandEncoder:(id<MTLComputeCommandEncoder>)computeCommandEncoder andIndices:(NSData *)indices
{
    [computeCommandEncoder setComputePipelineState:swapGlyphsState];
    [computeCommandEncoder setBuffer:generationBuffer offset:0 atIndex:0];
    [computeCommandEncoder setBytes:indices.bytes length:indices.length atIndex:1];
    [computeCommandEncoder dispatchThreads:MTLSizeMake(generationSize, 1, 1) threadsPerThreadgroup:MTLSizeMake(512, 1, 1)];
}

- (void)annealWithComputeCommandEncoder:(id<MTLComputeCommandEncoder>)computeCommandEncoder indices:(NSData *)indices beforeFitnesses:(id<MTLBuffer>)beforeFitnesses afterFitnesses:(id<MTLBuffer>)afterFitnesses
{
    [computeCommandEncoder setComputePipelineState:swapGlyphsState];
    [computeCommandEncoder setBuffer:generationBuffer offset:0 atIndex:0];
    [computeCommandEncoder setBytes:indices.bytes length:indices.length atIndex:1];
    id<MTLBuffer> buffers[] = {beforeFitnesses, afterFitnesses};
    NSUInteger offsets[] = {0, 0};
    [computeCommandEncoder setBuffers:buffers offsets:offsets withRange:NSMakeRange(2, 2)];
    float randoms[generationSize];
    for (uint32_t i = 0; i < generationSize; ++i)
        randoms[i] = (float)arc4random() / UINT32_MAX;
    [computeCommandEncoder setBytes:randoms length:sizeof(randoms) atIndex:4];
    [computeCommandEncoder dispatchThreads:MTLSizeMake(generationSize, 1, 1) threadsPerThreadgroup:MTLSizeMake(512, 1, 1)];
}

- (void)simulateWithCallback:(void (^)(float))callback
{
    {
        id<MTLCommandBuffer> initialCommandBuffer = [queue commandBuffer];
        id<MTLComputeCommandEncoder> initialComputeCommandEncoder = [initialCommandBuffer computeCommandEncoder];
        [self computeFitnessesWithComputeCommandEncoder:initialComputeCommandEncoder andFitnessBuffer:fitnessABuffer];
        [initialComputeCommandEncoder endEncoding];
        [initialCommandBuffer addCompletedHandler:^(id<MTLCommandBuffer> commandBuffer) {
            assert(commandBuffer.error == nil);
        }];
        [initialCommandBuffer commit];
        assert(state == NO);
        state = YES;
    }

    const int iterations = 1;
    for (int i = 0; i < 1; ++i) {
        NSMutableData *indices = [NSMutableData dataWithLength:sizeof(uint32_t) * generationSize * 2];
        uint32_t* ptr = [indices mutableBytes];
        for (uint32_t i = 0; i < generationSize * 2; ++i)
            ptr[i] = arc4random_uniform(glyphCount);

        id<MTLBuffer> beforeFitnesses;
        id<MTLBuffer> afterFitnesses;
        if (state) {
            beforeFitnesses = fitnessABuffer;
            afterFitnesses = fitnessBBuffer;
        } else {
            beforeFitnesses = fitnessBBuffer;
            afterFitnesses = fitnessABuffer;
        }

        id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];
        id<MTLComputeCommandEncoder> computeCommandEncoder = [commandBuffer computeCommandEncoder];
        [self swapGlyphsWithComputeCommandEncoder:computeCommandEncoder andIndices:indices];
        [self computeFitnessesWithComputeCommandEncoder:computeCommandEncoder andFitnessBuffer:afterFitnesses];
        [self annealWithComputeCommandEncoder:computeCommandEncoder indices:indices beforeFitnesses:beforeFitnesses afterFitnesses:afterFitnesses];
        [computeCommandEncoder endEncoding];
        if (i == iterations - 1) {
            id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
            [blitEncoder synchronizeResource:afterFitnesses];
            [blitEncoder endEncoding];
        }
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> commandBuffer) {
            assert(commandBuffer.error == nil);
            if (i == iterations - 1) {
                float* fitnesses = afterFitnesses.contents;
                assert(self->urlCount > 0);
                float best = fitnesses[0];
                for (uint32_t i = 0; i < self->urlCount; ++i)
                    best = MAX(best, fitnesses[i]);
                dispatch_async(dispatch_get_main_queue(), ^{
                    callback(best);
                });
            }
        }];
        [commandBuffer commit];
        state = !state;
    }
}

- (float)simulate
{
    __block float result;
    [self simulateWithCallback:^(float v) {
        result = v;
        CFRunLoopStop(CFRunLoopGetMain());
    }];
    CFRunLoopRun();
    return result;
}

@end
