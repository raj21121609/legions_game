// GlitchVerse - Subtle Screen Glitch Shader
// GL Compatibility renderer safe.
// Techniques: horizontal band displacement, RGB channel separation, sparse digital pixel noise.
// All intensities are gated by the "intensity" uniform (0.0 = invisible / zero-cost, 1.0 = full).

shader_type canvas_item;

// -- Tunables exposed to GDScript --------------------------------------------
uniform float intensity        : hint_range(0.0, 1.0) = 0.0;   // master gate
uniform float displacement_str : hint_range(0.0, 1.0) = 0.4;   // band shift strength
uniform float rgb_split_str    : hint_range(0.0, 1.0) = 0.35;  // RGB lateral offset
uniform float noise_density    : hint_range(0.0, 1.0) = 0.15;  // digital pixel noise
uniform float time_seed        : hint_range(0.0, 1000.0) = 0.0; // driven by script each frame

// -- Helpers -----------------------------------------------------------------
float rand(vec2 co) {
    return fract(sin(dot(co, vec2(127.1, 311.7))) * 43758.5453123);
}
float rand1(float t) {
    return fract(sin(t * 127.1 + 311.7) * 43758.5453);
}

void fragment() {
    // Early-out: when intensity is zero the rect is fully transparent, no work done.
    if (intensity <= 0.001) {
        COLOR = vec4(0.0);
        return;
    }

    vec2 uv = SCREEN_UV;

    // -- 1. Horizontal band displacement -------------------------------------
    float band_seed   = floor(uv.y * 80.0 + time_seed * 3.7);
    float band_rand   = rand1(band_seed);
    float band_active = step(0.92 - displacement_str * 0.3, band_rand);
    float shift_dir   = sign(rand1(band_seed + 7.3) - 0.5);
    float shift_amt   = band_rand * displacement_str * 0.012 * band_active * shift_dir;
    vec2 disp_uv      = clamp(uv + vec2(shift_amt, 0.0), vec2(0.0), vec2(1.0));

    // -- 2. RGB channel separation -------------------------------------------
    float rgb_offset = rgb_split_str * 0.006;
    float rgb_seed   = time_seed * 0.53;
    float r_shift    = (rand1(rgb_seed)        - 0.5) * 2.0 * rgb_offset;
    float b_shift    = (rand1(rgb_seed + 17.1) - 0.5) * 2.0 * rgb_offset;
    vec2 uv_r = clamp(disp_uv + vec2(r_shift, 0.0), vec2(0.0), vec2(1.0));
    vec2 uv_b = clamp(disp_uv + vec2(b_shift, 0.0), vec2(0.0), vec2(1.0));

    float col_r = texture(SCREEN_TEXTURE, uv_r).r;
    float col_g = texture(SCREEN_TEXTURE, disp_uv).g;
    float col_b = texture(SCREEN_TEXTURE, uv_b).b;
    float col_a = texture(SCREEN_TEXTURE, disp_uv).a;
    vec4 base = vec4(col_r, col_g, col_b, col_a);

    // -- 3. Sparse digital pixel noise ---------------------------------------
    float noise_rand      = rand(vec2(uv.x * 500.0 + time_seed, uv.y * 500.0));
    float noise_threshold = 1.0 - noise_density * 0.03;
    float noise_val       = step(noise_threshold, noise_rand);
    float noise_col       = rand(vec2(uv.y + time_seed * 1.3, noise_rand));
    vec4 noise_pixel      = vec4(noise_col, noise_col * 0.8, 1.0, 1.0) * noise_val;

    // -- 4. Blend with intensity gate ----------------------------------------
    vec4 glitched   = mix(base, base + noise_pixel, noise_val * 0.6);
    vec4 unmodified = texture(SCREEN_TEXTURE, uv);
    COLOR = mix(unmodified, glitched, intensity);
}
