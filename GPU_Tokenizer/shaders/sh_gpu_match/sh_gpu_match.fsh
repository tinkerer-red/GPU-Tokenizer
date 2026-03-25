varying vec2 v_vTexcoord;

#define GPU_TOKEN_OMIT 0.0
#define GPU_TOKEN_ISOLATE 1.0
#define GPU_TOKEN_CONCATENATE 2.0

#define GPU_TOK_TYPE_UNMATCHED 0.0
#define GPU_TOK_TYPE_DELIMITER 1.0
#define GPU_TOK_TYPE_IGNORE 2.0
#define GPU_TOK_TYPE_PATTERN 3.0

#define GPU_TOK_OP_MATCH 0.0
#define GPU_TOK_OP_CHAR 1.0
#define GPU_TOK_OP_CLASS 2.0
#define GPU_TOK_OP_ANY 3.0
#define GPU_TOK_OP_JUMP 4.0
#define GPU_TOK_OP_SPLIT 5.0

#define GPU_TOK_NULL_INDEX 255.0
#define GPU_TOK_MAX_SHADER_STATES 64
#define GPU_TOK_MAX_EPSILON_PASSES 16
#define GPU_TOK_MAX_MATCH_OUTER 65535


// gm_BaseTexture = input bytes
uniform sampler2D u_texProgram;     // NFA program texture
uniform vec2      u_srcSize;        // Input texture dimensions
uniform vec2      u_matchSize;      // Output match texture dimensions
uniform vec2      u_progSize;       // Program texture dimensions
uniform float     u_totalBytes;
uniform float     u_numStates;
uniform float     u_startState;
uniform float     u_numClasses;
uniform float     u_stateTableOff;  // = 4.0
uniform float     u_classTableOff;  // = 4 + numStates*4
uniform float     u_typeMapOff;     // = classTableOff + numClasses*256

float fetchByte(float idx) {
    float pixel = floor(idx / 4.0);
    float chan = mod(idx, 4.0);
    vec2 uv = (vec2(mod(pixel, u_srcSize.x), floor(pixel / u_srcSize.x)) + 0.5) / u_srcSize;
    vec4 t = texture2D(gm_BaseTexture, uv);
    if (chan < 0.5) return t.r;
    if (chan < 1.5) return t.g;
    if (chan < 2.5) return t.b;
    return t.a;
}

float fetchProg(float idx) {
    float pixel = floor(idx / 4.0);
    float chan = mod(idx, 4.0);
    vec2 uv = (vec2(mod(pixel, u_progSize.x), floor(pixel / u_progSize.x)) + 0.5) / u_progSize;
    vec4 t = texture2D(u_texProgram, uv);
    if (chan < 0.5) return t.r;
    if (chan < 1.5) return t.g;
    if (chan < 2.5) return t.b;
    return t.a;
}

float readProg(float idx) {
    return floor(fetchProg(idx) * 255.0 + 0.5);
}

// Read state: returns vec4(op, edgeA, edgeB, data) as integers
vec4 readState(float stateIdx) {
    float base = u_stateTableOff + stateIdx * 4.0;
    return vec4(readProg(base), readProg(base + 1.0), readProg(base + 2.0), readProg(base + 3.0));
}

// Check class membership
bool classMatches(float classId, float byteVal) {
    float off = u_classTableOff + classId * 256.0 + byteVal;
    return fetchProg(off) > 0.5;
}

// Check type map
float getType(float byteVal) {
    return readProg(u_typeMapOff + byteVal);
}

void main() {
    vec2 px = floor(v_vTexcoord * u_matchSize);
    float pixelIdx = px.y * u_matchSize.x + px.x;

    // Each pixel computes 2 match lengths (positions P0 and P1)
    float pos0 = pixelIdx * 2.0;
    float pos1 = pos0 + 1.0;

    vec4 result = vec4(0.0);

    for (int posLoop = 0; posLoop < 2; posLoop++) {
        float startPos = (posLoop == 0) ? pos0 : pos1;
        float bestLen = 0.0;

        if (startPos >= u_totalBytes) {
            // Past end - match length = 0
        } else {
            // Skip if this byte is delimiter or ignore
            float startType = getType(floor(fetchByte(startPos) * 255.0 + 0.5));
            if (startType == GPU_TOK_TYPE_DELIMITER || startType == GPU_TOK_TYPE_IGNORE) {
                // delimiter or ignore - no pattern match starts here
            } else {
                // Initialize state set with epsilon closure from start state
                float curr[GPU_TOK_MAX_SHADER_STATES];
                float next[GPU_TOK_MAX_SHADER_STATES];
                for (int s = 0; s < GPU_TOK_MAX_SHADER_STATES; s++) { curr[s] = 0.0; next[s] = 0.0; }

                // Seed start state
                curr[int(u_startState)] = 1.0;

                // Epsilon closure on curr
                for (int pass = 0; pass < GPU_TOK_MAX_EPSILON_PASSES; pass++) {
                    bool changed = false;
                    for (int s = 0; s < GPU_TOK_MAX_SHADER_STATES; s++) {
                        if (curr[s] < 0.5) continue;
                        if (float(s) >= u_numStates) continue;
                        vec4 st = readState(float(s));
                        if (st.r == GPU_TOK_OP_JUMP) { // JUMP
                            if (st.g < GPU_TOK_NULL_INDEX && curr[int(st.g)] < 0.5) { curr[int(st.g)] = 1.0; changed = true; }
                        }
                        if (st.r == GPU_TOK_OP_SPLIT) { // SPLIT
                            if (st.g < GPU_TOK_NULL_INDEX && curr[int(st.g)] < 0.5) { curr[int(st.g)] = 1.0; changed = true; }
                            if (st.b < GPU_TOK_NULL_INDEX && curr[int(st.b)] < 0.5) { curr[int(st.b)] = 1.0; changed = true; }
                        }
                    }
                    if (!changed) break;
                }

                // Check if MATCH reachable at start (zero-length match)
                for (int s = 0; s < GPU_TOK_MAX_SHADER_STATES; s++) {
                    if (curr[s] > 0.5 && float(s) < u_numStates) {
                        vec4 st = readState(float(s));
                        if (st.r == GPU_TOK_OP_MATCH) bestLen = 0.001;  // mark as "match found, length 0"
                    }
                }

                // Simulate NFA byte by byte
                float fi = startPos;
                float bytesConsumed = 0.0;
                for (int outer = 0; outer < GPU_TOK_MAX_MATCH_OUTER; outer++) {
                    if (fi >= u_totalBytes) break;

                    float curByte = fetchByte(fi);
                    float curByteVal = floor(curByte * 255.0 + 0.5);

                    // Compute next state set
                    for (int s = 0; s < GPU_TOK_MAX_SHADER_STATES; s++) next[s] = 0.0;

                    bool anyActive = false;
                    for (int s = 0; s < GPU_TOK_MAX_SHADER_STATES; s++) {
                        if (curr[s] < 0.5) continue;
                        if (float(s) >= u_numStates) continue;
                        vec4 st = readState(float(s));

                        // OP_CHAR = 1
                        if (st.r == GPU_TOK_OP_CHAR && st.a == curByteVal) {
                            if (st.g < GPU_TOK_NULL_INDEX) { next[int(st.g)] = 1.0; anyActive = true; }
                        }
                        // OP_CLASS = 2
                        if (st.r == GPU_TOK_OP_CLASS && classMatches(st.a, curByteVal)) {
                            if (st.g < GPU_TOK_NULL_INDEX) { next[int(st.g)] = 1.0; anyActive = true; }
                        }
                        // OP_ANY = 3
                        if (st.r == GPU_TOK_OP_ANY) {
                            if (st.g < GPU_TOK_NULL_INDEX) { next[int(st.g)] = 1.0; anyActive = true; }
                        }
                    }

                    if (!anyActive) break;

                    // Epsilon closure on next
                    for (int pass = 0; pass < GPU_TOK_MAX_EPSILON_PASSES; pass++) {
                        bool changed2 = false;
                        for (int s = 0; s < GPU_TOK_MAX_SHADER_STATES; s++) {
                            if (next[s] < 0.5) continue;
                            if (float(s) >= u_numStates) continue;
                            vec4 st = readState(float(s));
                            if (st.r == GPU_TOK_OP_JUMP) {
                                if (st.g < GPU_TOK_NULL_INDEX && next[int(st.g)] < 0.5) { next[int(st.g)] = 1.0; changed2 = true; }
                            }
                            if (st.r == GPU_TOK_OP_SPLIT) {
                                if (st.g < GPU_TOK_NULL_INDEX && next[int(st.g)] < 0.5) { next[int(st.g)] = 1.0; changed2 = true; }
                                if (st.b < GPU_TOK_NULL_INDEX && next[int(st.b)] < 0.5) { next[int(st.b)] = 1.0; changed2 = true; }
                            }
                        }
                        if (!changed2) break;
                    }

                    bytesConsumed += 1.0;

                    // Check if MATCH is reachable
                    for (int s = 0; s < GPU_TOK_MAX_SHADER_STATES; s++) {
                        if (next[s] > 0.5 && float(s) < u_numStates) {
                            vec4 st = readState(float(s));
                            if (st.r == GPU_TOK_OP_MATCH) bestLen = bytesConsumed;
                        }
                    }

                    // Swap curr = next
                    for (int s = 0; s < GPU_TOK_MAX_SHADER_STATES; s++) curr[s] = next[s];
                    fi += 1.0;
                }
            }
        }

        // Pack match length as 2 bytes (lo, hi)
        float len = (bestLen < 0.01) ? 0.0 : floor(bestLen);
        float lo = mod(len, 256.0) / 255.0;
        float hi = floor(len / 256.0) / 255.0;

        if (posLoop == 0) { result.r = lo; result.g = hi; }
        else { result.b = lo; result.a = hi; }
    }

    gl_FragColor = result;
}