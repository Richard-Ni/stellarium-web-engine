/* Stellarium Web Engine - Copyright (c) 2022 - Stellarium Labs SRL
 *
 * This program is licensed under the terms of the GNU AGPL v3, or
 * alternatively under a commercial licence.
 *
 * The terms of the AGPL v3 license can be found in the main directory of this
 * repository.
 */

/*
 * Procedural sea, used by the 'live-ocean' landscape.  Unlike the panorama
 * landscapes there is no texture at all: the whole lower hemisphere is shaded
 * from the view direction and the sun position, so the reflection follows the
 * real sun instead of being baked in for one time of the day.
 *
 * The water is a flat plane at the geometry level; the waves are only a
 * perturbation of the normal, evaluated at the point where the view ray
 * meets the plane, so the tessellation stays as coarse as the fog's.  A
 * Schlick fresnel term mixes the dark body colour into the reflected sky,
 * which is what gives the bright band at the horizon, and a Blinn-Phong lobe
 * adds the glitter of the sun, and of the moon once the sun has set.  The
 * wave normals are what break that glitter up into the usual sparkling path
 * instead of one smooth streak.
 *
 * The reflected sky is an analytic colour, not the star field that was
 * actually drawn: sampling that back would need an offscreen render target,
 * which the renderer does not have.
 *
 * There are no waves and no time dependency here: everything is a function
 * of the view direction and the sun position only.
 */

#ifdef GL_ES
precision mediump float;
#endif

uniform lowp    vec4        u_color;
uniform mediump vec3        u_sun;        // Sun direction, observed frame.
uniform mediump vec4        u_moon;       // Moon direction + phase.
uniform mediump float       u_strength;   // Scales the specular reflection.
uniform mediump float       u_floor;      // Minimum ground brightness setting.
// highp: mediump may be fp16, whose ulp reaches half a second after ten
// minutes of accumulated time, and tens of metres out at the wave positions
// near the horizon.  Both turn the waves into noise.
uniform highp   float       u_time;       // Seconds, for the waves.

varying highp   vec3        v_dir;        // View direction, observed frame.

#ifdef VERTEX_SHADER

#includes "projections.glsl"

attribute highp   vec4       a_pos;
attribute highp   vec3       a_sky_pos;

void main()
{
    gl_Position = proj(a_pos.xyz);
    v_dir = a_sky_pos;
}

#endif
#ifdef FRAGMENT_SHADER

// Water at normal incidence reflects about 2% of the light.
const mediump float F0 = 0.02;
// Two lobes: a tight one for the core of the glitter path and a wide one
// for the scatter around it.  A single tight lobe reads as a laser beam.
const mediump float SHININESS = 300.0;
const mediump float SHININESS_WIDE = 24.0;
// Colour of the water itself, what is left where nothing is reflected.
const mediump vec3 DEEP = vec3(0.020, 0.070, 0.110);

// Eye height above the water, in metres.  Sets how fast the waves shrink
// with distance, so it is really a look control rather than a measurement.
const highp float EYE_HEIGHT = 2.0;

/*
 * Slope of the water surface at a point, as the gradient of a sum of
 * directional waves.  Deep water dispersion, w = sqrt(g k), keeps the long
 * swell moving faster than the ripples riding on it.
 *
 * `dist` attenuates each wave by its own wavenumber, so the short ones are
 * gone by the time they would alias into noise near the horizon.
 */
mediump vec2 wave_slope(highp vec2 p, highp float dist)
{
    mediump vec2 g = vec2(0.0);
    highp float k, w, att, phase;
    mediump float amp;

    #define WAVE(dir, wavenumber, amplitude)                                 \
        k = wavenumber;                                                      \
        w = sqrt(9.81 * k);                                                  \
        att = 1.0 / (1.0 + dist * k * 0.010);                                \
        amp = (amplitude) * att;                                             \
        phase = k * dot(dir, p) - w * u_time;                                \
        g += amp * k * cos(phase) * (dir);

    WAVE(vec2( 1.000,  0.000), 0.32, 0.075)
    WAVE(vec2( 0.707,  0.707), 0.71, 0.038)
    WAVE(vec2(-0.588,  0.809), 1.63, 0.016)
    WAVE(vec2( 0.914, -0.407), 3.40, 0.007)
    #undef WAVE

    return g;
}

/*
 * Glitter of one light source, with the perturbed normal.  Two lobes, the
 * tight one for the core of the path and the wide one for the scatter
 * around it.
 */
mediump float glitter(highp vec3 dir, mediump vec3 light, mediump vec3 n)
{
    mediump vec3 h = normalize(vec3(light) - vec3(dir));
    mediump float n_dot_h = max(dot(n, h), 0.0);
    return pow(n_dot_h, SHININESS) + 0.06 * pow(n_dot_h, SHININESS_WIDE);
}

void main()
{
    highp vec3 dir = normalize(v_dir);
    mediump vec3 sun = normalize(u_sun);

    // The tiles are coarse and straddle the horizon, so the cut is done per
    // fragment rather than by dropping whole tiles.
    mediump float below = smoothstep(0.0, -0.004, dir.z);
    if (below == 0.0) discard;

    // Where this ray meets the water, and how far away that is.  The
    // distance runs away to infinity at the horizon, which is exactly the
    // foreshortening the waves need.
    highp float dist = EYE_HEIGHT / max(-dir.z, 1e-4);
    highp vec2 surface = dir.xy * dist;
    mediump vec3 n = normalize(vec3(-wave_slope(surface, dist), 1.0));

    // Schlick.  Grazing angles reflect nearly everything, and now that the
    // normal moves it is the waves that decide which facets are grazing.
    mediump float cos_i = clamp(dot(-dir, n), 0.0, 1.0);
    mediump float fresnel = F0 + (1.0 - F0) * pow(1.0 - cos_i, 5.0);

    mediump vec3 moon = normalize(u_moon.xyz);
    mediump float sun_up = smoothstep(-0.05, 0.02, sun.z);
    mediump float moon_up = smoothstep(-0.05, 0.02, moon.z);
    // A thin crescent lights the water far less than a full moon.
    mediump float moonlight = u_moon.w * moon_up;

    // The shader has its own day/night model, so the brightness setting only
    // comes in as the floor below which the sea stops getting darker.
    mediump float day = max(smoothstep(-0.12, 0.15, sun.z),
                            0.12 * moonlight);
    day = max(day, u_floor);

    // Crude stand in for the sky we are reflecting: dark blue at night, warm
    // while the sun is near the horizon, blue once it is up.  Without the
    // night step the sea keeps a sunset tint in the middle of the night.
    mediump vec3 sky = mix(vec3(0.05, 0.07, 0.13),
                           vec3(0.75, 0.42, 0.20),
                           smoothstep(-0.25, 0.0, sun.z));
    sky = mix(sky, vec3(0.35, 0.52, 0.78), smoothstep(0.0, 0.30, sun.z));

    mediump vec3 color = mix(DEEP, sky, fresnel) * day;

    if (sun_up > 0.0) {
        mediump vec3 sun_color = mix(vec3(1.0, 0.45, 0.20),
                                     vec3(1.0, 0.95, 0.85),
                                     smoothstep(0.0, 0.35, sun.z));
        color += sun_color * glitter(dir, sun, n)
               * fresnel * 25.0 * sun_up * u_strength;
    }

    // The moon path, fading in as the sun goes down so the two do not add up
    // in broad daylight where the moon reflection would not be visible.
    if (moonlight > 0.0) {
        mediump float night = 1.0 - smoothstep(-0.10, 0.10, sun.z);
        color += vec3(0.80, 0.85, 1.0) * glitter(dir, moon, n)
               * fresnel * 3.0 * moonlight * night * u_strength;
    }

    gl_FragColor = vec4(color, below * u_color.a);
}

#endif
