//
//  SimulatedAnnealing.metal
//  Optimize
//
//  Created by Myles C. Maxfield on 1/30/20.
//  Copyright © 2020 Litherum. All rights reserved.
//

#include <metal_stdlib>

using namespace metal;

constant uint32_t glyphCount [[function_constant(1)]];
constant uint32_t urlCount [[function_constant(2)]];
constant float exponent [[function_constant(3)]];
constant float maximumSlope [[function_constant(4)]];

void swap(device uint32_t* order, uint32_t index0, uint32_t index1) {
    uint32_t store = order[index0];
    order[index0] = order[index1];
    order[index1] = store;
}

kernel void swapGlyphs(device uint32_t* generation [[buffer(0)]], const device uint32_t* indices [[buffer(1)]], uint tid [[thread_position_in_grid]]) {
    uint generationIndex = tid;
    device uint32_t* order = generation + glyphCount * generationIndex;
    uint32_t index0 = indices[2 * generationIndex + 0];
    uint32_t index1 = indices[2 * generationIndex + 1];
    swap(order, index0, index1);
}

kernel void anneal(device uint32_t* generation [[buffer(0)]], const device uint32_t* indices [[buffer(1)]], device float* beforeFitnesses [[buffer(2)]], device float* afterFitnesses [[buffer(3)]], const device float* randoms [[buffer(4)]], const device float& temperature [[buffer(5)]], uint tid [[thread_position_in_grid]]) {
    uint generationIndex = tid;
    device uint32_t* order = generation + glyphCount * generationIndex;
    uint32_t index0 = indices[2 * generationIndex + 0];
    uint32_t index1 = indices[2 * generationIndex + 1];
    float beforeFitness = beforeFitnesses[generationIndex];
    float afterFitness = afterFitnesses[generationIndex];
    float randomNumber = randoms[generationIndex];

    // Higher values decrease the probability of moving to a new state which is worse than the current state.
    const float scalar = pow(temperature, exponent) * maximumSlope;
    if ((afterFitness - beforeFitness) * scalar + 1 < randomNumber) {
        // The neighbor is worse than the current state.
        // Go back to the current state.
        // Luckily, we can just swap the glyphs again to get back to where we were before.
        swap(order, index0, index1);
        afterFitnesses[generationIndex] = beforeFitness;
    }
}