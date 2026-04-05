/**
 * LocalStorage-backed custom shader store.
 * Stores user-created/edited shaders under a "custom" group.
 * Key: "simpleshader_custom" → JSON array of { name, source }
 */

const STORAGE_KEY = "simpleshader_custom";

export function loadCustomShaders() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

export function saveCustomShaders(list) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(list));
}

/** Save or update a shader by name. Returns the updated list. */
export function upsertCustomShader(name, source) {
  const list = loadCustomShaders();
  const idx = list.findIndex((s) => s.name === name);
  if (idx >= 0) {
    list[idx].source = source;
  } else {
    list.push({ name, source });
  }
  saveCustomShaders(list);
  return list;
}

/** Rename a custom shader. Returns the updated list. */
export function renameCustomShader(oldName, newName) {
  const list = loadCustomShaders();
  const idx = list.findIndex((s) => s.name === oldName);
  if (idx >= 0) list[idx].name = newName;
  saveCustomShaders(list);
  return list;
}

/** Delete a custom shader. Returns the updated list. */
export function deleteCustomShader(name) {
  const list = loadCustomShaders().filter((s) => s.name !== name);
  saveCustomShaders(list);
  return list;
}
