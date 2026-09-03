/* Stellarium Web Engine - Copyright (c) 2022 - Stellarium Labs SRL
 *
 * This program is licensed under the terms of the GNU AGPL v3, or
 * alternatively under a commercial licence.
 *
 * The terms of the AGPL v3 license can be found in the main directory of this
 * repository.
 */

/*
 * LICENSING, PLEASE READ BEFORE SHIPPING THIS.
 *
 * sea_octave() and the octave loop constants in sea_height() are taken from
 * "Seascape" by Alexander Alekseev (TDM), https://shadertoy.com/view/Ms2SD1,
 * which is CC BY-NC-SA 3.0.  That is incompatible with this repository on
 * both counts: NonCommercial rules out the commercial licence this engine is
 * also offered under, and ShareAlike would want the derivative back under
 * CC BY-NC-SA rather than the AGPL.  Before this goes anywhere public,
 * either get permission from the author (tdmaav@gmail.com, who has granted
 * commercial licences before) or replace those two pieces with an
 * independent implementation.  The rest of this file is our own.
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
 * The slope field is a few directional wave trains, which carry the wind
 * direction and the right dispersion, plus fractal noise, which is what stops
 * the result from looking like the sum of six sines that it would otherwise
 * be.  Both are read through a warped domain for the same reason.
 *
 * The reflected sky is an analytic colour, not the star field that was
 * actually drawn: sampling that back would need an offscreen render target,
 * which the renderer does not have.
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
// Three lobes rather than one: real sun glitter is scattered over facets of
// every size, and a single exponent gives it the hard edge of polished
// plastic.  Exponents and weights follow the usual ocean shader values.
const mediump float SHININESS_SHARP = 512.0;
const mediump float SHININESS_MED   = 128.0;
const mediump float SHININESS_BROAD =  32.0;
// Colour of the water itself, what is left where nothing is reflected.
const mediump vec3 DEEP = vec3(0.020, 0.070, 0.110);

// Eye height above the water, in metres: a low bluff rather than standing in
// the shallows.  At 2m the bottom of a typical view lands 2.7m away, less
// than a sixth of the dominant swell, so the near water had no wave in it at
// all.  This is a look control, not a measurement.
const highp float EYE_HEIGHT = 12.0;

/*
 * Wave field, after Alexander Alekseev's "Seascape" (shadertoy Ms2SD1,
 * CC BY-NC-SA 3.0).  The shape of a wave is the whole point here: a sum of
 * sines is smooth everywhere and reads as plastic, while the 1-|sin| basis
 * below has sharp crests and flat troughs, which is what water does.
 */
const highp   float SEA_FREQ   = 0.30;   // 1/m, so a 21m dominant swell.
const mediump float SEA_HEIGHT = 0.34;   // Metres, per octave before decay.
const mediump float SEA_CHOPPY = 4.0;
const highp   float SEA_SPEED  = 1.6;    // m/s.
// Rotates by 37 degrees and scales by two between octaves.  Without the
// rotation the octaves line up and the surface shows a grid.
const mediump mat2 OCTAVE_M = mat2(1.6, 1.2, -1.2, 1.6);

/*
 * Value noise.  The hash input is wrapped first: our surface coordinates run
 * to thousands of metres near the horizon, and feeding those to sin() at the
 * usual magic constants lands well past the point where its argument keeps
 * any precision, which shows up as streaks.  The 512 cell period this
 * introduces is far larger than anything visible.
 */
highp float hash12(highp vec2 p)
{
    p = mod(p, 512.0);
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

highp float noise2(highp vec2 p)
{
    highp vec2 i = floor(p);
    highp vec2 f = fract(p);
    highp vec2 u = f * f * (3.0 - 2.0 * f);
    return -1.0 + 2.0 * mix(mix(hash12(i + vec2(0.0, 0.0)),
                                hash12(i + vec2(1.0, 0.0)), u.x),
                            mix(hash12(i + vec2(0.0, 1.0)),
                                hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

/*
 * One octave.  The domain warp on the first line is what keeps the ridges
 * from running in straight lines.
 */
mediump float sea_octave(highp vec2 uv, mediump float choppy)
{
    uv += noise2(uv);
    mediump vec2 wv = 1.0 - abs(sin(uv));
    mediump vec2 swv = abs(cos(uv));
    wv = mix(wv, swv, wv);
    return pow(1.0 - pow(wv.x * wv.y, 0.65), choppy);
}

/*
 * Height of the water at a point.  Two counter travelling copies per octave,
 * which interfere instead of merely sliding past, and each octave attenuated
 * by its own wavenumber so the fine detail is gone before it can alias into
 * the horizon.
 */
highp float sea_height(highp vec2 p, highp float dist)
{
    highp float freq = SEA_FREQ;
    mediump float amp = SEA_HEIGHT;
    mediump float choppy = SEA_CHOPPY;
    highp float t = 1.0 + u_time * SEA_SPEED;
    highp vec2 uv = p;
    uv.x *= 0.75;

    highp float h = 0.0, d, att, k = SEA_FREQ;
    // Three octaves close up, two further out where the third is attenuated
    // to nothing anyway and only costs.
    for (int i = 0; i < 3; i++) {
        if (i == 2 && dist > 350.0) break;
        att = 1.0 / (1.0 + dist * k * 0.004);
        d  = sea_octave((uv + t) * freq, choppy);
        d += sea_octave((uv - t) * freq, choppy);
        h += d * amp * att;
        uv = OCTAVE_M * uv;
        freq *= 1.9;
        amp *= 0.22;
        k *= 3.8;   // uv doubles and freq goes up 1.9, so the wavenumber does
        choppy = mix(choppy, 1.0, 0.2);
    }
    return h;
}

/*
 * Shape of the sky we are mirroring, bright at the horizon and deeper
 * overhead, warm while the sun is low and neutral once it has set.  Only the
 * hue varies here; `day` further down does the dimming, so that the minimum
 * brightness setting stays a single lever.
 *
 * Making this depend on the reflected direction rather than being one flat
 * colour is what gives the water its texture: a tilted wave face mirrors a
 * different part of the sky, instead of merely more or less of the same one.
 */
mediump vec3 sky_shape(mediump float up, mediump float sun_z)
{
    mediump float twilight = smoothstep(-0.25, 0.0, sun_z);
    mediump float daylight = smoothstep(0.0, 0.30, sun_z);

    mediump vec3 hor = mix(vec3(0.90, 0.50, 0.22),
                           vec3(0.55, 0.66, 0.85), daylight);
    mediump vec3 zen = mix(vec3(0.30, 0.26, 0.40),
                           vec3(0.18, 0.34, 0.66), daylight);
    hor = mix(vec3(0.25, 0.30, 0.45), hor, twilight);
    zen = mix(vec3(0.13, 0.16, 0.30), zen, twilight);

    return mix(hor, zen, smoothstep(0.0, 0.45, up));
}

/*
 * Glitter of one light source, with the perturbed normal.  Two lobes, the
 * tight one for the core of the path and the wide one for the scatter
 * around it.
 */
mediump float lobe(mediump float d, mediump float s)
{
    // Normalising by (s + 8) / 8pi keeps a tighter lobe from also being a
    // brighter one, so the three can be weighted by how much of the surface
    // each really represents.
    return pow(d, s) * (s + 8.0) / (25.1327);
}

mediump float glitter(highp vec3 dir, mediump vec3 light, mediump vec3 n)
{
    mediump vec3 h = normalize(vec3(light) - vec3(dir));
    mediump float d = max(dot(n, h), 0.0);
    return 0.55 * lobe(d, SHININESS_SHARP)
         + 0.30 * lobe(d, SHININESS_MED)
         + 0.15 * lobe(d, SHININESS_BROAD);
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

    // Normal by finite differences.  The epsilon grows with the square of
    // the distance, which is Dave Hoskins' trick on the original: it filters
    // the far water instead of letting it shimmer pixel by pixel.
    highp float eps = max(dist * dist * 3e-4, 0.05);
    highp float h0 = sea_height(surface, dist);
    highp float hx = sea_height(surface + vec2(eps, 0.0), dist);
    highp float hy = sea_height(surface + vec2(0.0, eps), dist);
    mediump vec3 n = normalize(vec3((h0 - hx) / eps, (h0 - hy) / eps, 1.0));

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

    // Which way the water sends the sky into the eye, and hence which part
    // of it we see on this wave face.
    mediump vec3 refl = reflect(dir, n);
    mediump vec3 sky = sky_shape(max(refl.z, 0.0), sun.z);

    mediump vec3 color = mix(DEEP, sky, fresnel) * day;

    // Light that goes into the water and scatters back out, strongest on the
    // faces turned towards the sun.  Weighted by 1 - fresnel, so it is what
    // is left looking steeply down, where the reflection has all but gone
    // and the waves would otherwise have no contrast at all.
    if (sun_up > 0.0) {
        mediump float sss = max(dot(n, sun), 0.0) * (1.0 - fresnel);
        color += vec3(0.05, 0.28, 0.20) * sss * sss * sun_up * day;
    }

    if (sun_up > 0.0) {
        mediump vec3 sun_color = mix(vec3(1.0, 0.45, 0.20),
                                     vec3(1.0, 0.95, 0.85),
                                     smoothstep(0.0, 0.35, sun.z));
        color += sun_color * glitter(dir, sun, n)
               * fresnel * 1.3 * sun_up * u_strength;
    }

    // The moon path, fading in as the sun goes down so the two do not add up
    // in broad daylight where the moon reflection would not be visible.
    if (moonlight > 0.0) {
        mediump float night = 1.0 - smoothstep(-0.10, 0.10, sun.z);
        color += vec3(0.80, 0.85, 1.0) * glitter(dir, moon, n)
               * fresnel * 0.18 * moonlight * night * u_strength;
    }

    gl_FragColor = vec4(color, below * u_color.a);
}

#endif
