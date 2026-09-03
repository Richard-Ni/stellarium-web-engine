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
 * The water is a flat horizontal plane.  A Schlick fresnel term mixes the
 * dark body colour into the reflected sky, which is what gives the bright
 * band at the horizon, and a Blinn-Phong lobe adds the sun glitter; the lobe
 * stretches into the usual vertical path on its own as the sun gets low.
 *
 * There are no waves and no time dependency here: everything is a function
 * of the view direction and the sun position only.
 */

#ifdef GL_ES
precision mediump float;
#endif

uniform lowp    vec4        u_color;
uniform mediump vec3        u_sun;        // Sun direction, observed frame.
uniform mediump float       u_strength;   // Scales the specular reflection.
uniform mediump float       u_floor;      // Minimum ground brightness setting.

varying mediump vec3        v_dir;        // View direction, observed frame.

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

void main()
{
    mediump vec3 dir = normalize(v_dir);
    mediump vec3 sun = normalize(u_sun);

    // The tiles are coarse and straddle the horizon, so the cut is done per
    // fragment rather than by dropping whole tiles.
    mediump float below = smoothstep(0.0, -0.004, dir.z);
    if (below == 0.0) discard;

    // Schlick, with the incidence angle measured against the flat surface.
    // Grazing angles near the horizon reflect nearly everything.
    mediump float cos_i = min(-dir.z, 1.0);
    mediump float fresnel = F0 + (1.0 - F0) * pow(1.0 - cos_i, 5.0);

    // The shader has its own day/night model, so the brightness setting only
    // comes in as the floor below which the sea stops getting darker.
    mediump float day = max(smoothstep(-0.12, 0.15, sun.z), u_floor);

    // Crude stand in for the sky we are reflecting: dark blue at night, warm
    // while the sun is near the horizon, blue once it is up.  Without the
    // night step the sea keeps a sunset tint in the middle of the night.
    mediump vec3 sky = mix(vec3(0.05, 0.07, 0.13),
                           vec3(0.75, 0.42, 0.20),
                           smoothstep(-0.25, 0.0, sun.z));
    sky = mix(sky, vec3(0.35, 0.52, 0.78), smoothstep(0.0, 0.30, sun.z));

    mediump vec3 color = mix(DEEP, sky, fresnel) * day;

    // Specular glitter.  The surface normal is +z, so n.h is just h.z.
    mediump float sun_up = smoothstep(-0.05, 0.02, sun.z);
    if (sun_up > 0.0) {
        mediump vec3 h = normalize(sun - dir);
        mediump float n_dot_h = max(h.z, 0.0);
        mediump float spec = pow(n_dot_h, SHININESS)
                           + 0.06 * pow(n_dot_h, SHININESS_WIDE);
        mediump vec3 sun_color = mix(vec3(1.0, 0.45, 0.20),
                                     vec3(1.0, 0.95, 0.85),
                                     smoothstep(0.0, 0.35, sun.z));
        color += sun_color * spec * fresnel * 25.0 * sun_up * u_strength;
    }

    gl_FragColor = vec4(color, below * u_color.a);
}

#endif
