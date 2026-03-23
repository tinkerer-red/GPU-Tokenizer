varying vec2 v_vTexcoord;

uniform vec2  u_compileSize;    // compile buffer texture dimensions
uniform vec2  u_lookupSize;     // output lookup texture dimensions
uniform float u_compileBytes;   // total bytes in compile buffer
uniform float u_numCtxRules;    // number of context rules
uniform float u_ctxDataOffset;  // byte offset of context data in output
uniform float u_unmatchedMode;  // 0=omit, 1=isolate, 2=concatenate

float fetchCompile(float idx) {
    float pixel = floor(idx / 4.0);
    float chan = mod(idx, 4.0);
    vec2 uv = (vec2(mod(pixel, u_compileSize.x), floor(pixel / u_compileSize.x)) + 0.5)
              / u_compileSize;
    vec4 t = texture2D(gm_BaseTexture, uv);
    if (chan < 0.5) return t.r;
    if (chan < 1.5) return t.g;
    if (chan < 2.5) return t.b;
    return t.a;
}

float readByte(float pos) {
    return floor(fetchCompile(pos) * 255.0 + 0.5);
}

// Skip past a null-terminated string. Returns position after the null.
float skipString(float pos) {
    float fp = pos;
    for (int s = 0; s < 1024; s++) {
        if (readByte(fp) == 0.0) return fp + 1.0;
        fp += 1.0;
    }
    return fp;
}

// Skip past a complete rule. Returns position of next rule.
float skipRule(float pos) {
    float rt = readByte(pos);
    if (rt == 1.0) {
        float ng = readByte(pos + 1.0);
        return pos + 2.0 + ng * 257.0;
    }
    if (rt == 2.0) {
        float p = pos + 1.0;
        p = skipString(p);
        p = skipString(p);
        p = skipString(p);
        return p + 1.0;
    }
    if (rt == 3.0 || rt == 4.0) return pos + 257.0;
    return pos + 1.0;
}

// ── TYPE MAP: is byte B a delimiter(1), ignored(2), pattern-matched(3), or unmatched(0)? ──
float computeType(float byteB) {
    float pos = 0.0;
    bool matched = false;
    for (int rule = 0; rule < 256; rule++) {
        float rt = readByte(pos);
        if (rt == 0.0) break;
        if (rt == 4.0) {
            if (fetchCompile(pos + 1.0 + byteB) > 0.5) return 2.0 / 255.0;
        }
        if (rt == 3.0) {
            if (fetchCompile(pos + 1.0 + byteB) > 0.5) return 1.0 / 255.0;
        }
        if (rt == 1.0) {
            float ng = readByte(pos + 1.0);
            float gOff = pos + 2.0;
            for (int g = 0; g < 32; g++) {
                if (float(g) >= ng) break;
                if (fetchCompile(gOff + 1.0 + byteB) > 0.5) { matched = true; break; }
                gOff += 257.0;
            }
        }
        pos = skipRule(pos);
    }
    return matched ? 3.0 / 255.0 : 0.0;
}

// ── MERGE TABLE: can byte A be followed by byte B within the same token? ──
bool computeMerge(float byteA, float byteB) {
    float pos = 0.0;
    for (int rule = 0; rule < 256; rule++) {
        float rt = readByte(pos);
        if (rt == 0.0) break;
        if (rt == 1.0) {
            float ng = readByte(pos + 1.0);
            float gOff = pos + 2.0;
            // Self-merge: repeating groups
            for (int g = 0; g < 32; g++) {
                if (float(g) >= ng) break;
                if (readByte(gOff) > 0.0) {
                    if (fetchCompile(gOff + 1.0 + byteA) > 0.5 &&
                        fetchCompile(gOff + 1.0 + byteB) > 0.5) return true;
                }
                gOff += 257.0;
            }
            // Sequential merge: adjacent groups
            gOff = pos + 2.0;
            for (int g = 0; g < 31; g++) {
                if (float(g) >= ng - 1.0) break;
                float gOff2 = gOff + 257.0;
                if (fetchCompile(gOff + 1.0 + byteA) > 0.5 &&
                    fetchCompile(gOff2 + 1.0 + byteB) > 0.5) return true;
                gOff += 257.0;
            }
        }
        pos = skipRule(pos);
    }
    return false;
}

// ── START-MERGE: can a token starting with byte S contain byte C? ──
bool computeStartMerge(float byteS, float byteC) {
    float pos = 0.0;
    for (int rule = 0; rule < 256; rule++) {
        float rt = readByte(pos);
        if (rt == 0.0) break;
        if (rt == 1.0) {
            float ng = readByte(pos + 1.0);
            float g0Off = pos + 2.0;
            if (fetchCompile(g0Off + 1.0 + byteS) > 0.5) {
                float gOff = pos + 2.0;
                for (int g = 0; g < 32; g++) {
                    if (float(g) >= ng) break;
                    if (fetchCompile(gOff + 1.0 + byteC) > 0.5) return true;
                    gOff += 257.0;
                }
            }
        }
        pos = skipRule(pos);
    }
    return false;
}

// ── CONTEXT START MAP: find longest-opener rule that starts with byte B ──
float computeCtxStart(float byteB) {
    float pos = 0.0;
    float bestRule = 0.0;
    float bestLen = 0.0;
    float ctxIdx = 0.0;
    for (int rule = 0; rule < 256; rule++) {
        float rt = readByte(pos);
        if (rt == 0.0) break;
        if (rt == 2.0) {
            float fb = readByte(pos + 1.0);
            if (fb == byteB) {
                float oLen = 0.0;
                float fp = pos + 1.0;
                for (int s = 0; s < 1024; s++) {
                    if (readByte(fp) == 0.0) break;
                    oLen += 1.0; fp += 1.0;
                }
                if (oLen > bestLen) {
                    bestLen = oLen;
                    bestRule = ctxIdx + 1.0;
                }
            }
            ctxIdx += 1.0;
        }
        pos = skipRule(pos);
    }
    return bestRule / 255.0;
}

// ── CONTEXT INDEX: compute one entry (4 bytes) for rule R ──
// Returns: vec4(offsetLo/255, offsetHi/255, nextRule/255, flags)
vec4 computeCtxIndex(float ruleR) {
    // First pass: find rule R's position and compute data offset
    float pos = 0.0;
    float curCtx = 0.0;
    float rulePos = 0.0;
    float dataOff = 0.0;
    for (int rule = 0; rule < 256; rule++) {
        float rt = readByte(pos);
        if (rt == 0.0) break;
        if (rt == 2.0) {
            if (curCtx == ruleR) { rulePos = pos; break; }
            float p = pos + 1.0;
            float strStart = p;
            p = skipString(p); p = skipString(p); p = skipString(p);
            dataOff += (p - strStart);
            curCtx += 1.0;
        }
        pos = skipRule(pos);
    }

    // Read opener first byte and length
    float firstByte = readByte(rulePos + 1.0);
    float myLen = 0.0;
    float fp = rulePos + 1.0;
    for (int s = 0; s < 1024; s++) {
        if (readByte(fp) == 0.0) break;
        myLen += 1.0; fp += 1.0;
    }

    // Read flags (after open\0close\0escape\0)
    float flagsPos = rulePos + 1.0;
    flagsPos = skipString(flagsPos);
    flagsPos = skipString(flagsPos);
    flagsPos = skipString(flagsPos);
    float flags = fetchCompile(flagsPos);

    // Find next rule in chain: same first byte, next-longest opener
    float nextRule = 0.0;
    float bestNextLen = 0.0;
    float searchPos = 0.0;
    float searchCtx = 0.0;
    for (int rule = 0; rule < 256; rule++) {
        float rt = readByte(searchPos);
        if (rt == 0.0) break;
        if (rt == 2.0) {
            if (searchCtx != ruleR) {
                float fb = readByte(searchPos + 1.0);
                if (fb == firstByte) {
                    float oLen = 0.0;
                    float fp2 = searchPos + 1.0;
                    for (int s = 0; s < 1024; s++) {
                        if (readByte(fp2) == 0.0) break;
                        oLen += 1.0; fp2 += 1.0;
                    }
                    if (oLen < myLen && oLen > bestNextLen) {
                        bestNextLen = oLen;
                        nextRule = searchCtx + 1.0;
                    }
                }
            }
            searchCtx += 1.0;
        }
        searchPos = skipRule(searchPos);
    }

    float offLo = mod(dataOff, 256.0);
    float offHi = floor(dataOff / 256.0);
    return vec4(offLo / 255.0, offHi / 255.0, nextRule / 255.0, flags);
}

// ── CONTEXT DATA: copy byte from compile buffer's context string data ──
float computeCtxData(float dataIdx) {
    float pos = 0.0;
    float dataOff = 0.0;
    for (int rule = 0; rule < 256; rule++) {
        float rt = readByte(pos);
        if (rt == 0.0) break;
        if (rt == 2.0) {
            float strStart = pos + 1.0;
            float p = strStart;
            p = skipString(p); p = skipString(p); p = skipString(p);
            float strLen = p - strStart;
            if (dataIdx < dataOff + strLen) {
                return fetchCompile(strStart + (dataIdx - dataOff));
            }
            dataOff += strLen;
        }
        pos = skipRule(pos);
    }
    return 0.0;
}

void main() {
    vec2 px = floor(v_vTexcoord * u_lookupSize);
    float baseIdx = (px.y * u_lookupSize.x + px.x) * 4.0;
    vec4 result = vec4(0.0);

    for (int ch = 0; ch < 4; ch++) {
        float outIdx = baseIdx;
        if (ch == 1) outIdx += 1.0;
        else if (ch == 2) outIdx += 2.0;
        else if (ch == 3) outIdx += 3.0;
        float value = 0.0;

        if (outIdx < 256.0) {
            // Type map
            value = computeType(outIdx);
        } else if (outIdx < 65792.0) {
            // Merge table
            float tIdx = outIdx - 256.0;
            float byteA = floor(tIdx / 256.0);
            float byteB = mod(tIdx, 256.0);
            bool merged = computeMerge(byteA, byteB);
            if (!merged && u_unmatchedMode == 2.0) {
                float tA = computeType(byteA);
                float tB = computeType(byteB);
                if (floor(tA * 255.0 + 0.5) == 0.0 && floor(tB * 255.0 + 0.5) == 0.0)
                    merged = true;
            }
            value = merged ? 1.0 : 0.0;
        } else if (outIdx < 131328.0) {
            // Start-merge table
            float tIdx = outIdx - 65792.0;
            float byteS = floor(tIdx / 256.0);
            float byteC = mod(tIdx, 256.0);
            bool sm = computeStartMerge(byteS, byteC);
            if (!sm && u_unmatchedMode == 2.0) {
                float tS = computeType(byteS);
                float tC = computeType(byteC);
                if (floor(tS * 255.0 + 0.5) == 0.0 && floor(tC * 255.0 + 0.5) == 0.0)
                    sm = true;
            }
            value = sm ? 1.0 : 0.0;
        } else if (outIdx < 131584.0) {
            // Context start map
            value = computeCtxStart(outIdx - 131328.0);
        } else if (outIdx < u_ctxDataOffset) {
            // Context index
            float idxOff = outIdx - 131584.0;
            float ruleR = floor(idxOff / 4.0);
            float comp = mod(idxOff, 4.0);
            if (ruleR < u_numCtxRules) {
                vec4 entry = computeCtxIndex(ruleR);
                if (comp < 0.5) value = entry.r;
                else if (comp < 1.5) value = entry.g;
                else if (comp < 2.5) value = entry.b;
                else value = entry.a;
            }
        } else {
            // Context data
            value = computeCtxData(outIdx - u_ctxDataOffset);
        }

        if (ch == 0) result.r = value;
        else if (ch == 1) result.g = value;
        else if (ch == 2) result.b = value;
        else result.a = value;
    }

    gl_FragColor = result;
}