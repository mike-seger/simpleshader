/**
 * Shadertoy export — converts playground GLSL to Shadertoy-compatible code.
 */

/** Convert a single chunk of playground GLSL to Shadertoy conventions. */
function convertChunk(src) {
  let out = src;

  // Convert @lil-gui const block → #define (before other replacements)
  out = out.replace(
    /\/\/\s*@lil-gui-start\n([\s\S]*?)\/\/\s*@lil-gui-end/g,
    (_, block) => block.split('\n').map(line => {
      const m = line.match(/^\s*const\s+\S+\s+(\w+)\s*=\s*([^;]+);/);
      return m ? `#define ${m[1]} ${m[2].trim()}` : line;
    }).join('\n')
  );

  // Remove WebGL1-specific declarations
  out = out.replace(/^#extension\s+GL_OES_standard_derivatives\s*:\s*\w+\s*\n/m, '');
  out = out.replace(/^precision\s+\w+\s+\w+;\s*\n/m, '');
  out = out.replace(/^uniform\s+vec2\s+u_resolution;[^\n]*\n/m, '');
  out = out.replace(/^uniform\s+float\s+u_time;[^\n]*\n/m, '');
  out = out.replace(/^uniform\s+sampler2D\s+u_channel\d+;[^\n]*\n/gm, '');

  // Replace playground uniforms with Shadertoy builtins
  out = out.replace(/\bu_time\b/g, 'iTime');
  out = out.replace(/\bu_resolution\b/g, 'iResolution.xy');
  out = out.replace(/\bu_channel0\b/g, 'iChannel0');
  out = out.replace(/\bu_channel1\b/g, 'iChannel1');

  // WebGL 1 → WebGL 2 (Shadertoy uses GLSL ES 3.0)
  out = out.replace(/\btexture2D\b/g, 'texture');

  // Replace GLSL ES output with Shadertoy conventions
  out = out.replace(/\bgl_FragCoord\.xy\b/g, 'fragCoord');
  out = out.replace(/\bgl_FragCoord\b/g, 'fragCoord');
  out = out.replace(/\bgl_FragColor\b/g, 'fragColor');
  out = out.replace(/\bvoid\s+main\s*\(\s*\)/g, 'void mainImage(out vec4 fragColor, in vec2 fragCoord)');

  return out;
}

/** Split source at // @pass markers (mirrors renderer._parsePasses logic). */
function splitPasses(src) {
  const passRe = /^\/\/\s*@pass\s+(\w+)(?:\s+size=([\w.]+),([\w.]+))?/;
  const lines = src.split('\n');
  const preamble = [];
  const passes = [];
  let cur = null;

  for (const line of lines) {
    const m = line.match(passRe);
    if (m) {
      if (cur) passes.push(cur);
      cur = { name: m[1], sizeTag: m[0], body: [] };
    } else if (cur) {
      cur.body.push(line);
    } else {
      preamble.push(line);
    }
  }
  if (cur) passes.push(cur);
  if (passes.length === 0) return null; // single-pass shader
  return { preamble: preamble.join('\n'), passes };
}

const BUFFER_NAMES = ['Buffer A', 'Buffer B', 'Buffer C', 'Buffer D'];

/**
 * Convert playground GLSL to Shadertoy-compatible code.
 * @param {string} src              Raw shader source
 * @param {(src: string) => Promise<string>} resolveIncludes  Resolves @include directives
 */
export async function toShadertoy(src, resolveIncludes) {
  // 1. Resolve @include directives (inline library files)
  let resolved = await resolveIncludes(src);

  // 2. Check for multipass
  const mp = splitPasses(resolved);

  if (!mp) {
    // Single-pass: straightforward conversion
    return convertChunk(resolved);
  }

  // Multipass: emit labelled sections
  const sections = [];
  const last = mp.passes.length - 1;

  for (let i = 0; i < mp.passes.length; i++) {
    const p = mp.passes[i];
    const full = mp.preamble + '\n' + p.body.join('\n');
    const converted = convertChunk(full);
    const label = i < last ? BUFFER_NAMES[i] || `Buffer ${i}` : 'Image';
    sections.push(
      `// ${'═'.repeat(60)}\n` +
      `// ══  Paste into Shadertoy tab: ${label}\n` +
      (i < last
        ? `// ══  Set ${BUFFER_NAMES[i] || 'Buffer ' + i} as iChannel0 on the next tab\n`
        : '') +
      `// ${'═'.repeat(60)}\n\n` +
      converted
    );
  }

  return sections.join('\n\n');
}
