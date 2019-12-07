//
//  PickAndPlace.metal
//  Optimize
//
//  Created by Litherum on 12/6/19.
//  Copyright © 2019 Litherum. All rights reserved.
//

#include <metal_stdlib>
#include "PickAndPlaceShared.h"

using namespace metal;

constant uint32_t glyphCount [[function_constant(0)]];
constant uint32_t glyphBitfieldSize [[function_constant(1)]];
constant uint32_t urlCount [[function_constant(2)]];
constant uint32_t generationSize [[function_constant(3)]];

constant constexpr uint32_t threshold = 8 * 170;
constant constexpr uint32_t unconditionalDownloadSize = 282828;
constant constexpr uint32_t fontSize = 1758483;

class Rotater {
public:
    Rotater(uint32_t glyphIndex, uint32_t rotationIndex) : glyphIndex(glyphIndex), rotationIndex(rotationIndex) {
    }

    uint32_t next() {
        uint32_t index;
        if (glyphIndex == rotationIndex)
            index = i;
        else if (i == glyphIndex) {
            if (offset == 0) {
                offset = 1;
                index = i + 1;
            } else {
                offset = 0;
                index = i - 1;
            }
        } else if (i == rotationIndex) {
            if (offset == 0)
                offset = -1;
            else
                offset = 0;
            index = glyphIndex;
        } else
            index = i + offset;
        ++i;
        return index;
    }

private:
    uint32_t glyphIndex;
    uint32_t rotationIndex;
    uint32_t i{0};
    int32_t offset{0};
};

inline bool glyphIsNecessary(device uint32_t* urlBitmaps, uint urlIndex, uint32_t glyph) {
    return urlBitmaps[glyphBitfieldSize * urlIndex + glyph / 8] & (1 << (glyph % 8));
}

kernel void possibleFitnesses(device uint32_t* generation [[buffer(0)]], device uint32_t* glyphSizes [[buffer(1)]], device uint32_t* urlBitmaps [[buffer(2)]], device uint32_t* output [[buffer(3)]], constant uint32_t& glyphIndex [[buffer(4)]], uint3 tid [[thread_position_in_grid]]) {
    uint generationIndex = tid.x;
    uint urlIndex = tid.y;
    uint rotationIndex = tid.z;
    
    uint32_t result = unconditionalDownloadSize + threshold;
    uint32_t unnecessarySize = 0;
    bool state = false;
    Rotater rotater(glyphIndex, rotationIndex);
    for (uint32_t i = 0; i < glyphCount; ++i) {
        uint32_t index = rotater.next();
        uint32_t glyph = generation[glyphCount * generationIndex + index];
        uint32_t size = glyphSizes[glyph];
        bool glyphIsNecessary = ::glyphIsNecessary(urlBitmaps, urlIndex, glyph);
        if (glyphIsNecessary) {
            result += size;
            if (!state) {
                result += min(unnecessarySize, threshold);
                unnecessarySize = 0;
            }
        } else
            unnecessarySize += size;
        state = glyphIsNecessary;
    }

    uint planeSize = glyphCount * urlCount;
    output[planeSize * generationIndex + glyphCount * urlIndex + rotationIndex] = result;
}

kernel void sumPossibleFitnesses(device uint32_t* possibleFitnesses [[buffer(0)]], device float* output [[buffer(1)]], uint2 tid [[thread_position_in_grid]]) {
    uint generationIndex = tid.x;
    uint rotationIndex = tid.y;

    uint planeSize = glyphCount * urlCount;
    float result = 0;
    for (uint32_t i = 0; i < urlCount; ++i)
        result += static_cast<float>(possibleFitnesses[planeSize * generationIndex + glyphCount * i + rotationIndex]) / static_cast<float>(fontSize);

    output[glyphCount * generationIndex + rotationIndex] = result;
}

kernel void selectBestPossibility(device float* possibleFitnesses [[buffer(0)]], device struct Best* output [[buffer(1)]], uint tid [[thread_position_in_grid]]) {
    uint generationIndex = tid;

    float bestValue = fontSize;
    uint32_t bestIndex = 0;
    for (uint32_t i = 0; i < glyphCount; ++i) {
        float fitness = possibleFitnesses[glyphCount * generationIndex + i];
        if (fitness < bestValue) {
            bestValue = fitness;
            bestIndex = 0;
        }
    }

    output[generationIndex].bestValue = bestValue;
    output[generationIndex].bestIndex = bestIndex;
}

kernel void performRotation(device uint32_t* generation [[buffer(0)]], device struct Best* bestData [[buffer(1)]], device uint32_t* output [[buffer(2)]], constant uint32_t& glyphIndex [[buffer(3)]], uint tid [[thread_position_in_grid]]) {
    uint generationIndex = tid;
    uint32_t rotationIndex = bestData[generationIndex].bestIndex;

    Rotater rotater(glyphIndex, rotationIndex);
    for (uint32_t i = 0; i < glyphCount; ++i) {
        uint32_t index = rotater.next();
        output[glyphCount * generationIndex + i] = generation[glyphCount * generationIndex + index];
    }
}
