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

void main(void) {
    // resolution and center in pixels
    vec2 res = vec2(adsk_result_w, adsk_result_h);
    vec2 center = 0.5 * res;

    // prevent dividing by zero in period
    float period = (Period == 0.0) ? 1.0 : Period;

    // choose time source: prefer host frame, then adsk_time, then UI Time
    float tHost = (frame != 0.0) ? frame : adsk_time;
    float t = (tHost != 0.0) ? tHost : Time;
    float nX = noise1D(t / period + SeedX);
    float nY = noise1D(t / period + SeedY);
    float nR = noise1D(t / period + SeedR);

    // offsets (pixels) and rotation (radians)
    float offsetX = nX * Translation;
    float offsetY = nY * Translation;
    // GLSL 1.20: avoid radians() dependency
    float rotRad  = nR * (Rotation * 0.017453292519943295);

    float cosA = cos(rotRad);
    float sinA = sin(rotRad);

    // auto-scale to avoid cropping
    float absCos = abs(cosA);
    float absSin = abs(sinA);
    float scaleRotW = (absCos * res.x + absSin * res.y) / max(1.0, res.x);
    float scaleRotH = (absCos * res.y + absSin * res.x) / max(1.0, res.y);
    float denomW = max(1.0, res.x - 2.0 * Translation);
    float denomH = max(1.0, res.y - 2.0 * Translation);
    float scaleTransW = res.x / denomW;
    float scaleTransH = res.y / denomH;
    float scale = max(max(scaleRotW, scaleRotH), max(scaleTransW, scaleTransH));
    if (!(scale > 0.0)) {
        scale = 1.0;
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

    // if outside, output black
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        gl_FragColor = vec4(0.0);
    } else {
        gl_FragColor = texture2D(front, uv);
    }
}


