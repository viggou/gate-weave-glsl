// Gate Weave - Baselight/Matchbox-style GLSL fragment shader
#version 120

// source image (Matchbox name expected by XML/UI)
uniform sampler2D front;

// result dimensions (provided by host)
uniform float adsk_result_w, adsk_result_h;

// parameters
uniform float Translation;  // pixels
uniform float Rotation;     // degrees
uniform float Period;       // time divisor
uniform float SeedX;
uniform float SeedY;
uniform float SeedR;
uniform float Time;         // animate over timeline
// optional host-provided time uniforms (if available)
uniform float frame;
uniform float adsk_time;
// controls for analog feel and edges
uniform bool AutoScale;     // zoom just enough for max rotation/translation (constant per settings)
uniform bool EdgeExtend;    // clamp sampling at image edges instead of black
uniform int  NoiseMode;     // 0: Value, 1: Perlin1D, 2: fBm (Perlin-based)

float smoothstep5(float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

// float hash to avoid integer bit ops portability issues
float hash1(float x) {
    return fract(sin(x * 127.1) * 43758.5453123);
}

float noise1D(float x) {
    float xi = floor(x);
    float frac = x - xi;
    float t = smoothstep5(frac);
    float v0 = hash1(xi);
    float v1 = hash1(xi + 1.0);
    return mix(v0, v1, t);
}

// simple 1D gradient (Perlin-style) noise mapped to [0,1]
float grad1(float i) {
    // hash to [-1,1]
    return -1.0 + 2.0 * fract(sin(i * 78.233) * 43758.5453);
}

float perlin1D(float x) {
    float i0 = floor(x);
    float i1 = i0 + 1.0;
    float t = x - i0;
    float g0 = grad1(i0);
    float g1 = grad1(i1);
    float u = smoothstep5(t);
    float n = mix(g0 * t, g1 * (t - 1.0), u); // ~[-0.5,0.5]
    return 0.5 + 0.5 * n;                     // [0,1]
}

// fBm (fractal Brownian motion) of 1D Perlin; 3 octaves, normalized to [0,1]
float fbm1D(float x, float seed) {
    float v = 0.0;
    float amp = 0.6;
    float f = 1.0;
    v += amp * perlin1D(x * f + seed * 1.123); // octave 1
    amp *= 0.5; f *= 2.0;
    v += amp * perlin1D(x * f + seed * 2.357); // octave 2
    amp *= 0.5; f *= 2.0;
    v += amp * perlin1D(x * f + seed * 3.789); // octave 3
    float norm = 0.6 + 0.3 + 0.15;
    return clamp(v / norm, 0.0, 1.0);
}

void main(void) {
    // resolution and center in pixels
    vec2 res = vec2(adsk_result_w, adsk_result_h);
    vec2 center = 0.5 * res;

    // prevent dividing by zero in period
    float period = (Period == 0.0) ? 1.0 : Period;

    // choose time source: prefer host frame, then adsk_time, then UI Time
    float tHost = (frame != 0.0) ? frame : adsk_time;
    float t = (tHost != 0.0) ? tHost : Time;
    float tx = t / period;
    float nX;
    float nY;
    float nR;
    if (NoiseMode == 1) { // Perlin
        nX = perlin1D(tx + SeedX);
        nY = perlin1D(tx + SeedY);
        nR = perlin1D(tx + SeedR);
    } else if (NoiseMode == 2) { // fBm
        nX = fbm1D(tx, SeedX);
        nY = fbm1D(tx, SeedY);
        nR = fbm1D(tx, SeedR);
    } else { // Value
        nX = noise1D(tx + SeedX);
        nY = noise1D(tx + SeedY);
        nR = noise1D(tx + SeedR);
    }

    // offsets (pixels) and rotation (radians)
    float offsetX = nX * Translation;
    float offsetY = nY * Translation;
    // GLSL 1.20: avoid radians() dependency; rot varies with noise
    float rotRad  = nR * (Rotation * 0.017453292519943295);

    float cosA = cos(rotRad);
    float sinA = sin(rotRad);

    // constant auto-scale (no breathing): use max rotation amplitude, not per-frame rot
    float scale = 1.0;
    if (AutoScale) {
        float rotMaxRad = Rotation * 0.017453292519943295;
        float cR = abs(cos(rotMaxRad));
        float sR = abs(sin(rotMaxRad));
        float scaleRotW = (cR * res.x + sR * res.y) / max(1.0, res.x);
        float scaleRotH = (cR * res.y + sR * res.x) / max(1.0, res.y);
        float denomW = max(1.0, res.x - 2.0 * Translation);
        float denomH = max(1.0, res.y - 2.0 * Translation);
        float scaleTransW = res.x / denomW;
        float scaleTransH = res.y / denomH;
        scale = max(max(scaleRotW, scaleRotH), max(scaleTransW, scaleTransH));
        if (!(scale > 0.0)) {
            scale = 1.0;
        }
    }

    // current pixel position in pixels
    vec2 p = gl_FragCoord.xy;

    // transform destination coord back into source space (inverse transform)
    vec2 d = p - center;
    d /= scale; // undo the zoom-in

    // inverse rotation
    vec2 s;
    s.x =  cosA * d.x + sinA * d.y;
    s.y = -sinA * d.x + cosA * d.y;

    // apply offsets and recenter
    vec2 samplePos = center + s - vec2(offsetX, offsetY);

    // convert back to UVs
    vec2 uv = samplePos / res;

    // edge handling
    if (EdgeExtend) {
        uv = clamp(uv, vec2(0.0), vec2(1.0));
        gl_FragColor = texture2D(front, uv);
    } else {
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            gl_FragColor = vec4(0.0);
        } else {
            gl_FragColor = texture2D(front, uv);
        }
    }
}


