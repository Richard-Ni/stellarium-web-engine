// Stellarium Web - Copyright (c) 2022 - Stellarium Labs SRL
//
// This program is licensed under the terms of the GNU AGPL v3, or
// alternatively under a commercial licence.
//
// The terms of the AGPL v3 license can be found in the main directory of this
// repository.

<template>
<v-dialog max-width='600' v-model="$store.state.showViewSettingsDialog" scrollable>
<v-card v-if="$store.state.showViewSettingsDialog" class="secondary white--text">
  <v-card-title><div class="text-h5">{{ $t('View settings') }}</div></v-card-title>
  <v-card-text class="settings-body">
    <v-expansion-panels accordion multiple v-model="openedSections">
      <v-expansion-panel v-for="section in sections" :key="section.title" class="secondary">
        <v-expansion-panel-header class="text-subtitle-1">{{ $t(section.title) }}</v-expansion-panel-header>
        <v-expansion-panel-content>

          <!-- Landscape selector, only in the first section. -->
          <v-select
            v-if="section.landscapeSelector"
            hide-details
            :label="$t('Landscape')"
            :items="landscapeOptions"
            item-text="text"
            item-value="value"
            v-model="currentLandscape"
          ></v-select>

          <!-- Projection selector, only in the view section. -->
          <v-select
            v-if="section.projectionSelector"
            hide-details
            :label="$t('Projection')"
            :items="projectionOptions"
            item-text="text"
            item-value="value"
            v-model="projection"
          ></v-select>

          <v-row dense>
            <v-col cols="12" sm="6" v-for="t in section.toggles" :key="t.path">
              <v-checkbox
                hide-details
                dense
                :label="$t(t.label)"
                :input-value="getValue(t.path)"
                @change="v => setValue(t.path, !!v)"
              ></v-checkbox>
            </v-col>
          </v-row>

          <div v-for="s in section.sliders" :key="s.path" class="slider-row">
            <v-slider
              hide-details
              dense
              thumb-label
              :label="$t(s.label)"
              :min="s.min"
              :max="s.max"
              :step="s.step"
              :value="getValue(s.path)"
              @input="v => setValue(s.path, v)"
            ></v-slider>
          </div>

          <!-- Settings that don't map one to one onto an engine property. -->
          <template v-if="section.specialSliders">
            <div class="slider-row">
              <v-slider
                hide-details
                dense
                thumb-label
                :label="$t('Label Density')"
                min="-3" max="3" step="0.5"
                :value="labelDensity"
                @input="v => labelDensity = v"
              ></v-slider>
            </div>
            <div class="slider-row">
              <v-slider
                hide-details
                dense
                :thumb-label="true"
                :label="$t('Limit Magnitude')"
                :min="LIMIT_MAG_MIN" :max="LIMIT_MAG_MAX" step="0.5"
                :value="displayLimitMag"
                @input="v => displayLimitMag = v"
              >
                <template v-slot:thumb-label="{ value }">
                  {{ value >= LIMIT_MAG_MAX ? '∞' : value }}
                </template>
              </v-slider>
            </div>
          </template>

          <div v-if="section.resetButton" class="text-right">
            <v-btn small text class="blue--text darken-1" @click.native="resetRendering()">{{ $t('Reset') }}</v-btn>
          </div>

        </v-expansion-panel-content>
      </v-expansion-panel>
    </v-expansion-panels>
  </v-card-text>
  <v-card-actions>
    <v-spacer></v-spacer><v-btn class="blue--text darken-1" text @click.native="$store.state.showViewSettingsDialog = false">Close</v-btn>
  </v-card-actions>
</v-card>
</v-dialog>
</template>

<script>

// Magnitude offset of the labels is a per-module setting in the engine, but
// it makes little sense to expose one slider per module, so the 'Label
// Density' slider drives all of them at once.
const HINTS_MAG_OFFSET_MODULES = [
  'stars', 'planets', 'dsos', 'minor_planets', 'comets', 'satellites'
]

// The engine uses 99 for 'no limit', which doesn't fit nicely on a slider, so
// the top of the slider range means unlimited.
const LIMIT_MAG_MIN = 1
const LIMIT_MAG_MAX = 25
const LIMIT_MAG_UNLIMITED = 99

// Engine defaults, used by the 'Reset' button of the rendering section.
// Keep in sync with core_init() in src/core.c and atmosphere_init().
const RENDERING_DEFAULTS = {
  bortle_index: 3,
  exposure_scale: 2,
  tonemapper_p: 2.2,
  star_linear_scale: 0.8,
  star_relative_scale: 1.1,
  center_hints_mag_offset: 0,
  display_limit_mag: LIMIT_MAG_UNLIMITED,
  'atmosphere.turbidity': 0.96
}

const SECTIONS = [
  {
    title: 'Landscape & Atmosphere',
    landscapeSelector: true,
    toggles: [
      { path: 'landscapes.visible', label: 'Show Landscape' },
      { path: 'landscapes.fog_visible', label: 'Fog' },
      { path: 'atmosphere.visible', label: 'Atmosphere' },
      { path: 'cardinals.visible', label: 'Cardinal Points' }
    ],
    sliders: [
      { path: 'landscapes.brightness_floor', label: 'Minimum Ground Brightness', min: 0, max: 1, step: 0.05 },
      { path: 'atmosphere.turbidity', label: 'Turbidity', min: 0.1, max: 10, step: 0.1 }
    ]
  },
  {
    title: 'Sky Objects',
    toggles: [
      { path: 'stars.visible', label: 'Stars' },
      { path: 'planets.visible', label: 'Planets' },
      { path: 'dsos.visible', label: 'Deep Sky Objects' },
      { path: 'minor_planets.visible', label: 'Minor Planets' },
      { path: 'comets.visible', label: 'Comets' },
      { path: 'satellites.visible', label: 'Satellites' },
      { path: 'meteors.visible', label: 'Meteors' },
      { path: 'milkyway.visible', label: 'Milky Way' },
      { path: 'dss.visible', label: 'DSS' },
      { path: 'planets.scale_moon', label: 'Enlarge Moon' }
    ],
    sliders: [
      { path: 'meteors.zhr', label: 'Meteor Rate (ZHR)', min: 0, max: 1000, step: 10 }
    ]
  },
  {
    title: 'Labels',
    toggles: [
      { path: 'stars.hints_visible', label: 'Star Names' },
      { path: 'planets.hints_visible', label: 'Planet Names' },
      { path: 'dsos.hints_visible', label: 'Deep Sky Object Names' },
      { path: 'minor_planets.hints_visible', label: 'Minor Planet Names' },
      { path: 'comets.hints_visible', label: 'Comet Names' },
      { path: 'satellites.hints_visible', label: 'Satellite Names' }
    ],
    specialSliders: true
  },
  {
    title: 'Constellations',
    toggles: [
      { path: 'constellations.lines_visible', label: 'Constellation Lines' },
      { path: 'constellations.labels_visible', label: 'Constellation Labels' },
      { path: 'constellations.images_visible', label: 'Constellations Art' },
      { path: 'constellations.bounds_visible', label: 'Constellation Boundaries' },
      { path: 'constellations.lines_animation', label: 'Lines Animation' },
      { path: 'constellations.show_only_pointed', label: 'Show Only Pointed' }
    ],
    sliders: [
      { path: 'constellations.illustrations_bscale', label: 'Art Brightness', min: 0, max: 2, step: 0.05 }
    ]
  },
  {
    title: 'Grids & Lines',
    toggles: [
      { path: 'lines.visible', label: 'All Lines' },
      { path: 'lines.azimuthal.visible', label: 'Azimuthal Grid' },
      { path: 'lines.equatorial.visible', label: 'Equatorial Grid (J2000)' },
      { path: 'lines.equatorial_jnow.visible', label: 'Equatorial Grid (of date)' },
      { path: 'lines.meridian.visible', label: 'Meridian Line' },
      { path: 'lines.ecliptic.visible', label: 'Ecliptic Line' },
      { path: 'lines.equator_line.visible', label: 'Celestial Equator' },
      { path: 'lines.boundary.visible', label: 'Projection Boundary' }
    ]
  },
  {
    title: 'View',
    projectionSelector: true,
    toggles: [
      { path: 'flip_view_horizontal', label: 'Flip Horizontally' },
      { path: 'flip_view_vertical', label: 'Flip Vertically' },
      { path: 'pointer.visible', label: 'Selection Pointer' },
      { path: 'observer.space', label: 'View from Space' }
    ]
  },
  {
    title: 'Brightness & Light Pollution',
    sliders: [
      { path: 'bortle_index', label: 'Light Pollution (Bortle)', min: 1, max: 9, step: 1 },
      { path: 'exposure_scale', label: 'Exposure', min: 0.1, max: 10, step: 0.1 },
      { path: 'tonemapper_p', label: 'Tone Mapping', min: 0.5, max: 5, step: 0.1 },
      { path: 'star_linear_scale', label: 'Star Size', min: 0.1, max: 3, step: 0.05 },
      { path: 'star_relative_scale', label: 'Star Contrast', min: 0.5, max: 3, step: 0.05 },
      { path: 'center_hints_mag_offset', label: 'Center Label Boost', min: 0, max: 5, step: 0.1 }
    ],
    resetButton: true
  }
]

// Read/write a dotted path on an object, without creating missing parents:
// lodash's set() would happily build them on the engine proxy.
const getPath = function (obj, path) {
  return path.split('.').reduce(function (o, key) {
    return (o === undefined || o === null) ? undefined : o[key]
  }, obj)
}

const setPath = function (obj, path, value) {
  const keys = path.split('.')
  const last = keys.pop()
  const target = keys.reduce(function (o, key) { return o[key] }, obj)
  target[last] = value
}

export default {
  data: function () {
    return {
      // Landscape & Atmosphere and Sky Objects opened by default.
      openedSections: [0, 1],
      sections: SECTIONS,
      LIMIT_MAG_MIN: LIMIT_MAG_MIN,
      LIMIT_MAG_MAX: LIMIT_MAG_MAX,
      landscapeOptions: [
        { text: 'Guereins', value: 'guereins' },
        { text: 'Ocean', value: 'ocean' }
      ],
      projectionOptions: [
        { text: this.$t('Perspective'), value: 1 },
        { text: this.$t('Stereographic'), value: 2 },
        { text: this.$t('Mercator'), value: 3 },
        { text: this.$t('Hammer'), value: 4 },
        { text: this.$t('Mollweide'), value: 5 }
      ]
    }
  },
  methods: {
    // The whole engine attribute tree is mirrored into $store.state.stel, so
    // we read from the store (reactive) and write to $stel.core (the engine).
    getValue: function (path) {
      return getPath(this.$store.state.stel, path)
    },
    setValue: function (path, newValue) {
      setPath(this.$stel.core, path, newValue)
    },
    resetRendering: function () {
      for (const path in RENDERING_DEFAULTS) {
        this.setValue(path, RENDERING_DEFAULTS[path])
      }
    }
  },
  computed: {
    currentLandscape: {
      get: function () {
        return this.$store.state.stel.landscapes.current_id
      },
      set: function (newValue) {
        this.$stel.core.landscapes.current_id = newValue
      }
    },
    projection: {
      get: function () {
        return this.$store.state.stel.projection
      },
      set: function (newValue) {
        this.$stel.core.projection = newValue
      }
    },
    labelDensity: {
      get: function () {
        return this.getValue(HINTS_MAG_OFFSET_MODULES[0] + '.hints_mag_offset')
      },
      set: function (newValue) {
        for (const module of HINTS_MAG_OFFSET_MODULES) {
          this.setValue(module + '.hints_mag_offset', newValue)
        }
      }
    },
    displayLimitMag: {
      get: function () {
        const mag = this.$store.state.stel.display_limit_mag
        return mag >= LIMIT_MAG_MAX ? LIMIT_MAG_MAX : mag
      },
      set: function (newValue) {
        this.$stel.core.display_limit_mag =
          newValue >= LIMIT_MAG_MAX ? LIMIT_MAG_UNLIMITED : newValue
      }
    }
  }
}
</script>

<style>
.input-group {
  margin: 0px;
}
.settings-body {
  max-height: 65vh;
}
.settings-body .v-expansion-panel::before {
  box-shadow: none;
}
.settings-body .v-expansion-panel-content__wrap {
  padding-bottom: 16px;
}
.slider-row {
  padding-top: 12px;
}
</style>
