/**
 * Doc renderer — fetches index.md, resolves child .md includes,
 * converts Markdown to HTML, and builds a side navigation.
 *
 * Include syntax in index.md:
 *   {{include path/to/child.md}}
 *
 * Uses marked (https://github.com/markedjs/marked) for Markdown rendering.
 */

import { marked } from "https://cdn.jsdelivr.net/npm/marked@15/+esm";

// Generate heading IDs and support [[kbd]] syntax
marked.use({
  renderer: {
    heading({ text, depth }) {
      const raw = text.replace(/<[^>]+>/g, "");
      const id = raw.toLowerCase().replace(/[^\w]+/g, "-").replace(/(^-|-$)/g, "");
      return `<h${depth} id="${id}">${text}</h${depth}>\n`;
    },
  },
  hooks: {
    preprocess(src) {
      return src.replace(/\[\[(.+?)\]\]/g, "<kbd>$1</kbd>");
    },
  },
});

const contentEl = document.getElementById("doc-content");
const navEl     = document.getElementById("doc-nav");

// ── Include resolution ────────────────────────────────────

async function resolveIncludes(src) {
  const re = /\{\{include\s+(.+?)\}\}/g;
  const matches = [...src.matchAll(re)];
  if (matches.length === 0) return src;

  const parts = [];
  let last = 0;
  for (const m of matches) {
    parts.push(src.slice(last, m.index));
    try {
      const res = await fetch(m[1].trim());
      if (res.ok) parts.push(await res.text());
      else parts.push(`> *Failed to load ${m[1].trim()}*`);
    } catch {
      parts.push(`> *Failed to load ${m[1].trim()}*`);
    }
    last = m.index + m[0].length;
  }
  parts.push(src.slice(last));
  return parts.join("\n");
}

// ── Navigation builder ───────────────────────────────────

function buildNav(html) {
  const parser = new DOMParser();
  const doc = parser.parseFromString(html, "text/html");
  const headings = doc.querySelectorAll("h1, h2");

  let nav = '<div class="nav-title">Contents</div>\n';
  for (const h of headings) {
    const id = h.id;
    const text = h.textContent;
    const indent = h.tagName === "H2" ? ' style="padding-left: 12px"' : "";
    nav += `<a href="#${id}"${indent}>${text}</a>\n`;
  }
  return nav;
}

// ── Scroll spy ────────────────────────────────────────────

function initScrollSpy() {
  const links = navEl.querySelectorAll("a[href^='#']");
  if (links.length === 0) return;

  // Click a nav link → immediately highlight it
  for (const link of links) {
    link.addEventListener("click", () => {
      for (const l of links) l.classList.remove("active");
      link.classList.add("active");
    });
  }

  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        for (const l of links) l.classList.remove("active");
        const active = navEl.querySelector(`a[href="#${entry.target.id}"]`);
        if (active) active.classList.add("active");
      }
    }
  }, { rootMargin: "-20% 0px -70% 0px" });

  for (const h of contentEl.querySelectorAll("h1[id], h2[id]")) {
    observer.observe(h);
  }
}

// ── Init ──────────────────────────────────────────────────

async function init() {
  try {
    const res = await fetch("doc.md");
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    let src = await res.text();
    src = await resolveIncludes(src);
    const html = marked.parse(src);
    contentEl.innerHTML = html;
    navEl.innerHTML = buildNav(html);
    initScrollSpy();
  } catch (e) {
    contentEl.innerHTML = `<p>Failed to load documentation: ${e.message}</p>`;
  }
}

init();
