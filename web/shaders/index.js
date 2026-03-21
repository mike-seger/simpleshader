/**
 * Shader index — single source of truth for all available shaders.
 * Each entry: { path: relative to web/, name: display name }
 * Grouped by folder.
 */
const SHADER_INDEX = [
  {
    folder: "xordev",
    shaders: [
      { name: "3D Fire",                      path: "shaders/xordev/3d-fire.glsl" },
      { name: "Accelerator",                  path: "shaders/xordev/accelerator.glsl" },
      { name: "Accretion",                    path: "shaders/xordev/accretion.glsl" },
      { name: "Ancient Alien Cathedral",      path: "shaders/xordev/ancient-alien-cathedral-tunnal.glsl" },
      { name: "Bagle",                        path: "shaders/xordev/bagle.glsl" },
      { name: "Black Hole",                   path: "shaders/xordev/blackhole.glsl" },
      { name: "Caustics",                     path: "shaders/xordev/caustics.glsl" },
      { name: "Cloudy Planet",                path: "shaders/xordev/cloudy-planet.glsl" },
      { name: "Complementary Flow",           path: "shaders/xordev/complementary-flow-adjusted.glsl" },
      { name: "Falls",                        path: "shaders/xordev/falls.glsl" },
      { name: "Global",                       path: "shaders/xordev/global.glsl" },
      { name: "Ionize",                       path: "shaders/xordev/ionize.glsl" },
      { name: "Jetstream",                    path: "shaders/xordev/jetstream.glsl" },
      { name: "Maelstrom",                    path: "shaders/xordev/maelstrom.glsl" },
      { name: "Milky",                        path: "shaders/xordev/milky.glsl" },
      { name: "Minecraft Tunnel",             path: "shaders/xordev/minecraft-tunnel.glsl" },
      { name: "Missiles",                     path: "shaders/xordev/missiles.glsl" },
      { name: "Neural",                       path: "shaders/xordev/neural.glsl" },
      { name: "Nova",                         path: "shaders/xordev/nova.glsl" },
      { name: "Parametrics",                  path: "shaders/xordev/parametrics.glsl" },
      { name: "Plasma Globe",                 path: "shaders/xordev/plasma-globe.glsl" },
      { name: "Quasar 2",                     path: "shaders/xordev/quasar-2.glsl" },
      { name: "Revive",                       path: "shaders/xordev/revive.glsl" },
      { name: "Shiny Disk",                   path: "shaders/xordev/shiny-disk.glsl" },
      { name: "Simple Neon Lines",            path: "shaders/xordev/simple-neon-lines.glsl" },
      { name: "Spellbound",                   path: "shaders/xordev/spellbound.glsl" },
      { name: "Stellar",                      path: "shaders/xordev/stellar.glsl" },
      { name: "String Theory",               path: "shaders/xordev/string-theory.glsl" },
      { name: "Surf 2",                       path: "shaders/xordev/surf-2.glsl" },
      { name: "Textures Microtorus",          path: "shaders/xordev/textures-microtorus.glsl" },
      { name: "Tonemapping Rings 2",          path: "shaders/xordev/tonemapping-rings-2.glsl" },
      { name: "Tonemapping Rings",            path: "shaders/xordev/tonemapping-rings.glsl" },
      { name: "Vortex 2",                     path: "shaders/xordev/vortex-2.glsl" },
      { name: "Vortex",                       path: "shaders/xordev/vortex.glsl" },
    ],
  },
];

export default SHADER_INDEX;
