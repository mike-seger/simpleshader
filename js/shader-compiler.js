/**
 * Shader source resolution — @include inlining and channel uniform injection.
 */

/**
 * Resolves // @include <path> directives by fetching and inlining each file.
 * @param {string} src      Raw shader source
 * @param {string} baseUrl  Absolute URL used to resolve relative include paths
 */
export async function resolveIncludes(src, baseUrl) {
  const includeRe = /^\s*\/\/\s*@include\s+(\S+)/;
  const lines = src.split('\n');
  const resolved = await Promise.all(lines.map(async line => {
    const m = line.match(includeRe);
    if (!m) return line;
    const url = new URL(m[1], baseUrl).href;
    const res = await fetch(url);
    if (!res.ok) throw new Error(`@include ${m[1]}: HTTP ${res.status}`);
    const text = await res.text();
    // Recursively resolve nested includes relative to the included file
    return resolveIncludes(text, url);
  }));
  return resolved.join('\n');
}

/**
 * Resolve @include paths relative to a shader's known path.
 * @param {string} source       Raw shader source
 * @param {string|null} currentPath  Shader file path (null for custom shaders)
 */
export function resolveForPath(source, currentPath) {
  const baseUrl = currentPath
    ? new URL(currentPath, window.location.href).href
    : window.location.href;
  return resolveIncludes(source, baseUrl);
}

/**
 * Inject uniform sampler2D declarations for any active media channels.
 * @param {string} resolved       Shader source (includes already resolved)
 * @param {object} mediaLoader    MediaLoader instance
 */
export function injectChannelUniforms(resolved, mediaLoader) {
  const chans = new Set(mediaLoader.hasMedia ? [...mediaLoader.channels.keys()] : []);
  if (chans.size === 0) return resolved;
  const decls = [...chans].sort()
    .map(c => `uniform sampler2D u_channel${c};`).join('\n');
  return resolved.replace(/(precision\s+\S+\s+\S+;)/, `$1\n${decls}`);
}
