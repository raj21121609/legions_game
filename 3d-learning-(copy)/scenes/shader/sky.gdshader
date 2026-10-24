shader_type sky;
render_mode use_half_res_pass; // Optimizes rendering execution overhead

uniform sampler2D sky_noise_texture : repeat_enable;
uniform float scroll_speed = 0.05;
uniform float twist_amount : hint_range(-10.0, 10.0) = 2.0;
uniform vec3 cosmic_void_color : source_color = vec3(0.05, 0.0, 0.1);
uniform vec3 energy_bright_color : source_color = vec3(0.2, 0.7, 1.0);
uniform float nebula_density : hint_range(0.1, 3.0) = 1.0;

void sky() {
    // EYEDIR provides the 3D direction vector from camera to sky dome coordinates
    vec3 dir = EYEDIR;
    
    // Map the 3D direction coordinates smoothly into a 2D equirectangular panorama layout
    float phi = atan(dir.z, dir.x);
    float theta = acos(dir.y);
    vec2 sky_uv = vec2(phi / (2.0 * 3.14159265) + 0.5, theta / 3.14159265);
    
    // Convert layout grid coordinates around a center horizon point to allow twisting
    vec2 centered_uv = sky_uv - vec2(0.5, 0.5);
    float rad_dist = length(centered_uv);
    float angle = atan(centered_uv.y, centered_uv.x);
    
    // Apply twisted distortion math based on distance to build swirling cosmic vortex look
    vec2 swirling_uv = vec2(
        angle / 3.14159265 * 0.5 + 0.5 + rad_dist * twist_amount, 
        rad_dist
    );
    
    // Move the coordinates over time across horizontal and vertical space 
    vec2 animated_uv = vec2(swirling_uv.x + TIME * scroll_speed, swirling_uv.y - TIME * (scroll_speed * 0.3));
    
    // Fetch and read the gray channels of your continuous looping noise
    float cosmic_noise = texture(sky_noise_texture, animated_uv).r;
    float blend_weight = smoothstep(0.3, 0.7, pow(cosmic_noise, nebula_density));
    
    // Output final color directly into the engine's background pass
    COLOR = mix(cosmic_void_color, energy_bright_color, blend_weight);
}
