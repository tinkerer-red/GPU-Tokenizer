varying vec2 v_vTexcoord;

uniform sampler2D u_texLookup;
uniform vec2      u_srcSize;
uniform vec2      u_outSize;
uniform float     u_totalBytes;
uniform float     u_unmatchedMode;
uniform float     u_lookupWidth;
uniform float     u_lookupHeight;
uniform float     u_ctxDataOffset;

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

float fetchLookup(float idx) {
    float pixel = floor(idx / 4.0);
    float chan = mod(idx, 4.0);
    vec2 uv = (vec2(mod(pixel, u_lookupWidth), floor(pixel / u_lookupWidth)) + 0.5)
              / vec2(u_lookupWidth, u_lookupHeight);
    vec4 t = texture2D(u_texLookup, uv);
    if (chan < 0.5) return t.r;
    if (chan < 1.5) return t.g;
    if (chan < 2.5) return t.b;
    return t.a;
}

// Type: 0=unmatched, 1=delimiter, 2=ignore, 3=pattern
float getType(float rawByte) {
    float idx = floor(rawByte * 255.0 + 0.5);
    return fetchLookup(idx);
}

// Byte-level merge: can byte A be followed by byte B?
bool canMerge(float rawA, float rawB) {
    float a = floor(rawA * 255.0 + 0.5);
    float b = floor(rawB * 255.0 + 0.5);
    return fetchLookup(256.0 + a * 256.0 + b) > 0.5;
}

// Byte-level start-merge: can a token starting with byte S contain byte C?
bool canStartMerge(float rawS, float rawC) {
    float a = floor(rawS * 255.0 + 0.5);
    float b = floor(rawC * 255.0 + 0.5);
    return fetchLookup(65792.0 + a * 256.0 + b) > 0.5;
}

float getCtxStart(float rawByte) {
    float idx = floor(rawByte * 255.0 + 0.5);
    return floor(fetchLookup(131328.0 + idx) * 255.0 + 0.5);
}

vec4 getCtxIndex(float ruleIdx) {
    float base = 131584.0 + (ruleIdx - 1.0) * 4.0;
    return vec4(fetchLookup(base), fetchLookup(base + 1.0),
                fetchLookup(base + 2.0), fetchLookup(base + 3.0));
}

float fetchCtxByte(float idx) {
    return fetchLookup(u_ctxDataOffset + idx);
}

bool matchCtxSequence(float dataOffset, float inputPos, out float nextOffset, out int outLen) {
    outLen = 0;
    float fk = 0.0;
    for (int k = 0; k < 1024; k++) {
        float rByte = fetchCtxByte(dataOffset + fk);
        float rVal = floor(rByte * 255.0 + 0.5);
        if (rVal == 0.0) {
            nextOffset = dataOffset + fk + 1.0;
            return (outLen > 0);
        }
        if (inputPos + fk >= u_totalBytes) {
            float sk = fk;
            for (int s = k; s < 1024; s++) {
                if (floor(fetchCtxByte(dataOffset + sk) * 255.0 + 0.5) == 0.0) {
                    nextOffset = dataOffset + sk + 1.0;
                    return false;
                }
                sk += 1.0;
            }
            nextOffset = dataOffset;
            return false;
        }
        float iByte = fetchByte(inputPos + fk);
        if (floor(iByte * 255.0 + 0.5) != rVal) {
            float sk = fk;
            for (int s = k; s < 1024; s++) {
                if (floor(fetchCtxByte(dataOffset + sk) * 255.0 + 0.5) == 0.0) {
                    nextOffset = dataOffset + sk + 1.0;
                    return false;
                }
                sk += 1.0;
            }
            nextOffset = dataOffset;
            return false;
        }
        outLen = outLen + 1;
        fk += 1.0;
    }
    nextOffset = dataOffset;
    return false;
}

void main() {
    vec2 px = floor(v_vTexcoord * u_outSize);
    float baseOutIdx = (px.y * u_outSize.x + px.x) * 4.0;
    vec4 result = vec4(0.0);

    for (int ch = 0; ch < 4; ch++) {
        float myOutIdx = baseOutIdx;
        if (ch == 1) myOutIdx += 1.0;
        else if (ch == 2) myOutIdx += 2.0;
        else if (ch == 3) myOutIdx += 3.0;
        float outByte = 0.0;

        float outPos = 0.0;
        bool inToken = false;
        float prevByte = 0.0;
        float startByte = 0.0;
        bool found = false;

        bool inContext = false;
        float ctxCloseOffset = 0.0;
        float ctxEscOffset = 0.0;
        int ctxCloseLen = 0;
        int ctxEscLen = 0;
        bool prevWasEsc = false;
        bool ctxKeepClose = true;
        bool ctxKeepEscape = true;
        int skipBytes = 0;

        float fi = 0.0;
        for (int outer = 0; outer < 65535; outer++) {
            if (found || fi >= u_totalBytes) break;
            for (int inner = 0; inner < 256; inner++) {
                if (found || fi >= u_totalBytes) break;
                if (skipBytes > 0) { skipBytes = skipBytes - 1; fi += 1.0; continue; }

                float curByte = fetchByte(fi);

                // === CONTEXT MODE ===
                if (inContext) {
                    if (prevWasEsc) {
                        prevWasEsc = false;
                        if (outPos == myOutIdx) { outByte = curByte; found = true; break; }
                        outPos += 1.0; fi += 1.0; continue;
                    }
                    if (ctxEscLen > 0) {
                        float dummy; int escLen;
                        bool escHit = matchCtxSequence(ctxEscOffset, fi, dummy, escLen);
                        if (escHit && escLen == ctxEscLen) {
                            prevWasEsc = true;
                            if (ctxKeepEscape) {
                                float fj = 0.0;
                                for (int eb = 0; eb < 1024; eb++) {
                                    if (eb >= escLen) break;
                                    if (outPos == myOutIdx) { outByte = fetchByte(fi + fj); found = true; }
                                    if (found) break;
                                    outPos += 1.0; fj += 1.0;
                                }
                                if (found) break;
                            }
                            skipBytes = escLen - 1; fi += 1.0; continue;
                        }
                    }
                    float dummy2; int closeLen;
                    bool closeHit = matchCtxSequence(ctxCloseOffset, fi, dummy2, closeLen);
                    if (closeHit && closeLen == ctxCloseLen) {
                        if (ctxKeepClose) {
                            float fj = 0.0;
                            for (int cb = 0; cb < 1024; cb++) {
                                if (cb >= closeLen) break;
                                if (outPos == myOutIdx) { outByte = fetchByte(fi + fj); found = true; }
                                if (found) break;
                                outPos += 1.0; fj += 1.0;
                            }
                            if (found) break;
                        }
                        skipBytes = closeLen - 1;
                        if (outPos == myOutIdx) { outByte = 0.0; found = true; break; }
                        outPos += 1.0; inContext = false; inToken = false;
                        fi += 1.0; continue;
                    }
                    if (outPos == myOutIdx) { outByte = curByte; found = true; break; }
                    outPos += 1.0; fi += 1.0; continue;
                }

                // === NORMAL MODE ===

                // Context openers
                float ruleIdx = getCtxStart(curByte);
                if (ruleIdx > 0.0) {
                    bool ctxMatched = false;
                    for (int r = 0; r < 1024; r++) {
                        if (ruleIdx == 0.0) break;
                        vec4 idx = getCtxIndex(ruleIdx);
                        float dataOff = floor(idx.r * 255.0 + 0.5) + floor(idx.g * 255.0 + 0.5) * 256.0;
                        float nextRule = floor(idx.b * 255.0 + 0.5);
                        float flags = floor(idx.a * 255.0 + 0.5);
                        float afterOpen; int openLen;
                        bool openHit = matchCtxSequence(dataOff, fi, afterOpen, openLen);
                        if (openHit) {
                            bool keepOpen = (mod(flags, 2.0) >= 0.5);
                            bool keepClose = (mod(floor(flags / 2.0), 2.0) >= 0.5);
                            bool keepEsc = (mod(floor(flags / 4.0), 2.0) >= 0.5);
                            if (inToken) {
                                if (outPos == myOutIdx) { outByte = 0.0; found = true; }
                                if (found) break;
                                outPos += 1.0; inToken = false;
                            }
                            if (keepOpen) {
                                float fj = 0.0;
                                for (int ob = 0; ob < 1024; ob++) {
                                    if (ob >= openLen) break;
                                    if (outPos == myOutIdx) { outByte = fetchByte(fi + fj); found = true; }
                                    if (found) break;
                                    outPos += 1.0; fj += 1.0;
                                }
                                if (found) break;
                            }
                            skipBytes = openLen - 1;
                            ctxCloseOffset = afterOpen;
                            ctxCloseLen = 0;
                            float fm = 0.0;
                            for (int m = 0; m < 1024; m++) {
                                if (floor(fetchCtxByte(afterOpen + fm) * 255.0 + 0.5) == 0.0) {
                                    ctxCloseLen = m; ctxEscOffset = afterOpen + fm + 1.0; break;
                                }
                                fm += 1.0;
                            }
                            ctxEscLen = 0; fm = 0.0;
                            for (int m = 0; m < 1024; m++) {
                                if (floor(fetchCtxByte(ctxEscOffset + fm) * 255.0 + 0.5) == 0.0) {
                                    ctxEscLen = m; break;
                                }
                                fm += 1.0;
                            }
                            inContext = true; inToken = true; prevWasEsc = false;
                            ctxKeepClose = keepClose; ctxKeepEscape = keepEsc;
                            ctxMatched = true; break;
                        }
                        ruleIdx = nextRule;
                    }
                    if (found) break;
                    if (ctxMatched) { fi += 1.0; continue; }
                }

                // Normal classification
                float curType = getType(curByte);
                float curTypeId = floor(curType * 255.0 + 0.5);

                if (curTypeId == 2.0) { fi += 1.0; continue; }
                if (curTypeId == 0.0) {
                    if (u_unmatchedMode == 0.0) { fi += 1.0; continue; }
                }
                if (curTypeId == 1.0) {
                    if (inToken) {
                        if (outPos == myOutIdx) { outByte = 0.0; found = true; break; }
                        outPos += 1.0; inToken = false;
                    }
                    fi += 1.0; continue;
                }

                // Token byte - check both merge tables using raw byte values
                if (inToken && (!canMerge(prevByte, curByte) || !canStartMerge(startByte, curByte))) {
                    if (outPos == myOutIdx) { outByte = 0.0; found = true; break; }
                    outPos += 1.0; inToken = false;
                }

                if (outPos == myOutIdx) { outByte = curByte; found = true; break; }
                outPos += 1.0;
                if (!inToken) startByte = curByte;
                inToken = true;
                prevByte = curByte;
                fi += 1.0;
            }
        }

        if (!found && inToken) {
            if (outPos == myOutIdx) { outByte = 0.0; found = true; }
        }

        if (ch == 0) result.r = outByte;
        else if (ch == 1) result.g = outByte;
        else if (ch == 2) result.b = outByte;
        else result.a = outByte;
    }

    gl_FragColor = result;
}