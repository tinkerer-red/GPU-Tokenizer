varying vec2 v_vTexcoord;

#define GPU_TOKEN_OMIT 0.0
#define GPU_TOKEN_ISOLATE 1.0
#define GPU_TOKEN_CONCATENATE 2.0

#define GPU_TOK_TYPE_UNMATCHED 0.0
#define GPU_TOK_TYPE_DELIMITER 1.0
#define GPU_TOK_TYPE_IGNORE 2.0
#define GPU_TOK_TYPE_PATTERN 3.0

#define GPU_TOK_MAX_CTX_SEQUENCE_BYTES 1024
#define GPU_TOK_MAX_MATCH_OUTER 65535


// gm_BaseTexture = input bytes
uniform sampler2D u_texMatch;       // Match length texture from pass 1
uniform sampler2D u_texProgram;     // NFA program (for type map + context data)
uniform vec2      u_srcSize;
uniform vec2      u_outSize;
uniform vec2      u_matchSize;
uniform vec2      u_progSize;
uniform float     u_totalBytes;
uniform float     u_unmatchedMode;
uniform float     u_typeMapOff;
uniform float     u_ctxStartOff;
uniform float     u_ctxIndexOff;
uniform float     u_ctxDataOff;

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

float getMatchLen(float pos) {
    float pixelIdx = floor(pos / 2.0);
    vec2 uv = (vec2(mod(pixelIdx, u_matchSize.x), floor(pixelIdx / u_matchSize.x)) + 0.5) / u_matchSize;
    vec4 t = texture2D(u_texMatch, uv);
    if (mod(pos, 2.0) < 0.5) {
        return floor(t.r * 255.0 + 0.5) + floor(t.g * 255.0 + 0.5) * 256.0;
    } else {
        return floor(t.b * 255.0 + 0.5) + floor(t.a * 255.0 + 0.5) * 256.0;
    }
}

float getType(float byteVal) {
    return readProg(u_typeMapOff + byteVal);
}

float getCtxStart(float byteVal) {
    return readProg(u_ctxStartOff + byteVal);
}

vec4 getCtxIndex(float ruleIdx) {
    float base = u_ctxIndexOff + (ruleIdx - 1.0) * 4.0;
    return vec4(fetchProg(base), fetchProg(base + 1.0),
                fetchProg(base + 2.0), fetchProg(base + 3.0));
}

float fetchCtxByte(float idx) {
    return fetchProg(u_ctxDataOff + idx);
}

bool matchCtxSequence(float dataOffset, float inputPos, out float nextOffset, out int outLen) {
    outLen = 0;
    float fk = 0.0;
    for (int k = 0; k < GPU_TOK_MAX_CTX_SEQUENCE_BYTES; k++) {
        float rByte = fetchCtxByte(dataOffset + fk);
        float rVal = floor(rByte * 255.0 + 0.5);
        if (rVal == 0.0) {
            nextOffset = dataOffset + fk + 1.0;
            return (outLen > 0);
        }
        if (inputPos + fk >= u_totalBytes) {
            float sk = fk;
            for (int s = k; s < GPU_TOK_MAX_CTX_SEQUENCE_BYTES; s++) {
                if (floor(fetchCtxByte(dataOffset + sk) * 255.0 + 0.5) == 0.0) {
                    nextOffset = dataOffset + sk + 1.0; return false;
                }
                sk += 1.0;
            }
            nextOffset = dataOffset; return false;
        }
        float iByte = fetchByte(inputPos + fk);
        if (floor(iByte * 255.0 + 0.5) != rVal) {
            float sk = fk;
            for (int s = k; s < GPU_TOK_MAX_CTX_SEQUENCE_BYTES; s++) {
                if (floor(fetchCtxByte(dataOffset + sk) * 255.0 + 0.5) == 0.0) {
                    nextOffset = dataOffset + sk + 1.0; return false;
                }
                sk += 1.0;
            }
            nextOffset = dataOffset; return false;
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
        bool found = false;

        // Context state
        bool inContext = false;
        float ctxCloseOffset = 0.0;
        float ctxEscOffset = 0.0;
        int ctxCloseLen = 0;
        int ctxEscLen = 0;
        bool prevWasEsc = false;
        bool ctxKeepClose = true;
        bool ctxKeepEscape = true;
        int skipBytes = 0;       // used ONLY for context open/close/escape skipping
        bool inUnmatched = false;
        int nfaRemaining = 0;    // bytes remaining in current NFA token span

        float fi = 0.0;
        for (int outer = 0; outer < GPU_TOK_MAX_MATCH_OUTER; outer++) {
            if (found || fi >= u_totalBytes) break;
            for (int inner = 0; inner < 256; inner++) {
                if (found || fi >= u_totalBytes) break;
                if (skipBytes > 0) { skipBytes = skipBytes - 1; fi += 1.0; continue; }

                float curByte = fetchByte(fi);
                float curByteVal = floor(curByte * 255.0 + 0.5);

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
                                for (int eb = 0; eb < GPU_TOK_MAX_CTX_SEQUENCE_BYTES; eb++) {
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
                            for (int cb = 0; cb < GPU_TOK_MAX_CTX_SEQUENCE_BYTES; cb++) {
                                if (cb >= closeLen) break;
                                if (outPos == myOutIdx) { outByte = fetchByte(fi + fj); found = true; }
                                if (found) break;
                                outPos += 1.0; fj += 1.0;
                            }
                            if (found) break;
                        }
                        skipBytes = closeLen - 1;
                        if (outPos == myOutIdx) { outByte = 0.0; found = true; break; }
                        outPos += 1.0; inContext = false;
                        fi += 1.0; continue;
                    }
                    if (outPos == myOutIdx) { outByte = curByte; found = true; break; }
                    outPos += 1.0; fi += 1.0; continue;
                }

                // === NORMAL MODE ===

                // Context openers are checked at EVERY position,
                // even within an NFA token span. Context takes priority.
                float ruleIdx = getCtxStart(curByteVal);
                if (ruleIdx > 0.0) {
                    bool ctxMatched = false;
                    for (int r = 0; r < GPU_TOK_MAX_CTX_SEQUENCE_BYTES; r++) {
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
                            // If mid-NFA token or mid-unmatched, terminate it
                            if (nfaRemaining > 0 || inUnmatched) {
                                if (outPos == myOutIdx) { outByte = 0.0; found = true; }
                                if (found) break;
                                outPos += 1.0;
                                nfaRemaining = 0;
                                inUnmatched = false;
                            }
                            if (keepOpen) {
                                float fj = 0.0;
                                for (int ob = 0; ob < GPU_TOK_MAX_CTX_SEQUENCE_BYTES; ob++) {
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
                            for (int m = 0; m < GPU_TOK_MAX_CTX_SEQUENCE_BYTES; m++) {
                                if (floor(fetchCtxByte(afterOpen + fm) * 255.0 + 0.5) == 0.0) {
                                    ctxCloseLen = m; ctxEscOffset = afterOpen + fm + 1.0; break;
                                }
                                fm += 1.0;
                            }
                            ctxEscLen = 0; fm = 0.0;
                            for (int m = 0; m < GPU_TOK_MAX_CTX_SEQUENCE_BYTES; m++) {
                                if (floor(fetchCtxByte(ctxEscOffset + fm) * 255.0 + 0.5) == 0.0) {
                                    ctxEscLen = m; break;
                                }
                                fm += 1.0;
                            }
                            inContext = true; prevWasEsc = false;
                            ctxKeepClose = keepClose; ctxKeepEscape = keepEsc;
                            ctxMatched = true; break;
                        }
                        ruleIdx = nextRule;
                    }
                    if (found) break;
                    if (ctxMatched) { fi += 1.0; continue; }
                }

                // If in NFA token span, emit this byte
                if (nfaRemaining > 0) {
                    if (outPos == myOutIdx) { outByte = curByte; found = true; break; }
                    outPos += 1.0;
                    nfaRemaining -= 1;
                    if (nfaRemaining == 0) {
                        if (outPos == myOutIdx) { outByte = 0.0; found = true; break; }
                        outPos += 1.0;
                    }
                    fi += 1.0; continue;
                }

                // Type check
                float curType = getType(curByteVal);
                if (curType == GPU_TOK_TYPE_IGNORE) { fi += 1.0; continue; }  // IGNORE
                if (curType == GPU_TOK_TYPE_DELIMITER) {  // DELIMITER
                    if (inUnmatched) {
                        if (outPos == myOutIdx) { outByte = 0.0; found = true; break; }
                        outPos += 1.0; inUnmatched = false;
                    }
                    fi += 1.0; continue;
                }

                // Check NFA match length at this position
                float matchLen = getMatchLen(fi);
                if (matchLen > 0.0) {
                    // End unmatched run if any
                    if (inUnmatched) {
                        if (outPos == myOutIdx) { outByte = 0.0; found = true; break; }
                        outPos += 1.0; inUnmatched = false;
                    }
                    // Emit first byte of NFA match
                    if (outPos == myOutIdx) { outByte = curByte; found = true; break; }
                    outPos += 1.0;
                    nfaRemaining = int(matchLen) - 1;
                    if (nfaRemaining == 0) {
                        // Single-byte match, emit null immediately
                        if (outPos == myOutIdx) { outByte = 0.0; found = true; break; }
                        outPos += 1.0;
                    }
                    fi += 1.0; continue;
                }

                // No match - unmatched byte
                if (u_unmatchedMode == GPU_TOKEN_OMIT) { fi += 1.0; continue; }  // OMIT
                if (u_unmatchedMode == GPU_TOKEN_ISOLATE) {  // ISOLATE
                    if (inUnmatched) {
                        if (outPos == myOutIdx) { outByte = 0.0; found = true; break; }
                        outPos += 1.0; inUnmatched = false;
                    }
                    if (outPos == myOutIdx) { outByte = curByte; found = true; break; }
                    outPos += 1.0;
                    if (outPos == myOutIdx) { outByte = 0.0; found = true; break; }
                    outPos += 1.0;
                    fi += 1.0; continue;
                }
                // CONCATENATE
                if (outPos == myOutIdx) { outByte = curByte; found = true; break; }
                outPos += 1.0;
                inUnmatched = true;
                fi += 1.0;
            }
        }

        // End of input
        if (!found && (inUnmatched || nfaRemaining > 0)) {
            if (outPos == myOutIdx) { outByte = 0.0; found = true; }
        }

        if (ch == 0) result.r = outByte;
        else if (ch == 1) result.g = outByte;
        else if (ch == 2) result.b = outByte;
        else result.a = outByte;
    }

    gl_FragColor = result;
}