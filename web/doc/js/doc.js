/**
 * Doc renderer — fetches index.md, resolves child .md includes,
 * converts Markdown to HTML, and builds a side navigation.
 *
 * Include syntax in index.md:
 *   {{include path/to/child.md}}
 *
 * Uses a lightweight built-in Markdown parser (no external dependencies).
 */

const contentEl = document.getElementById("doc-content");
const navEl     = document.getElementById("doc-nav");

// ── Minimal Markdown → HTML ───────────────────────────────

function md(src) {
  let html = "";
  const lines = src.split("\n");
  let i = 0;
  let inCode = false;
  let codeLang = "";
  let codeLines = [];
  let inList = false;
  let listType = "";

  function closeList() {
    if (inList) {
      html += listType === "ol" ? "</ol>\n" : "</ul>\n";
      inList = false;
    }
  }

  function inline(text) {
    // Images
    text = text.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1">');
    // Links
    text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
    // Bold + italic
    text = text.replace(/\*\*\*(.+?)\*\*\*/g, "<strong><em>$1</em></strong>");
    // Bold
    text = text.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
    // Italic
    text = text.replace(/\*(.+?)\*/g, "<em>$1</em>");
    // Inline code
    text = text.replace(/`([^`]+)`/g, "<code>$1</code>");
    // Kbd
    text = text.replace(/\[\[(.+?)\]\]/g, "<kbd>$1</kbd>");
    return text;
  }

  while (i < lines.length) {
    const line = lines[i];

    // Fenced code block
    if (/^```/.test(line)) {
      if (!inCode) {
        closeList();
        inCode = true;
        codeLang = line.slice(3).trim();
        codeLines = [];
      } else {
        const escaped = codeLines.join("\n")
          .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        html += `<pre><code>${escaped}</code></pre>\n`;
        inCode = false;
      }
      i++;
      continue;
    }
    if (inCode) {
      codeLines.push(line);
      i++;
      continue;
    }

    // Blank line
    if (/^\s*$/.test(line)) {
      closeList();
      i++;
      continue;
    }

    // Headings
    const hm = line.match(/^(#{1,6})\s+(.+)/);
    if (hm) {
      closeList();
      const level = hm[1].length;
      const text = inline(hm[2]);
      const id = hm[2].toLowerCase().replace(/[^\w]+/g, "-").replace(/(^-|-$)/g, "");
      html += `<h${level} id="${id}">${text}</h${level}>\n`;
      i++;
      continue;
    }

    // Horizontal rule
    if (/^[-*_]{3,}\s*$/.test(line)) {
      closeList();
      html += "<hr>\n";
      i++;
      continue;
    }

    // Blockquote
    if (/^>\s?/.test(line)) {
      closeList();
      const qLines = [];
      while (i < lines.length && /^>\s?/.test(lines[i])) {
        qLines.push(lines[i].replace(/^>\s?/, ""));
        i++;
      }
      html += `<blockquote><p>${inline(qLines.join(" "))}</p></blockquote>\n`;
      continue;
    }

    // Unordered list
    const ulm = line.match(/^(\s*)[-*+]\s+(.+)/);
    if (ulm) {
      if (!inList || listType !== "ul") {
        closeList();
        html += "<ul>\n";
        inList = true;
        listType = "ul";
      }
      html += `<li>${inline(ulm[2])}</li>\n`;
      i++;
      continue;
    }

    // Ordered list
    const olm = line.match(/^(\s*)\d+\.\s+(.+)/);
    if (olm) {
      if (!inList || listType !== "ol") {
        closeList();
        html += "<ol>\n";
        inList = true;
        listType = "ol";
      }
      html += `<li>${inline(olm[2])}</li>\n`;
      i++;
      continue;
    }

    // Table
    if (line.includes("|") && i + 1 < lines.length && /^\|?\s*[-:]+/.test(lines[i + 1])) {
      closeList();
      const parseRow = (r) => r.replace(/^\|/, "").replace(/\|$/, "").split("|").map(c => c.trim());
      const headers = parseRow(line);
      i += 2; // skip header + separator
      html += "<table><thead><tr>";
      for (const h of headers) html += `<th>${inline(h)}</th>`;
      html += "</tr></thead><tbody>\n";
      while (i < lines.length && lines[i].includes("|")) {
        const cells = parseRow(lines[i]);
        html += "<tr>";
        for (const c of cells) html += `<td>${inline(c)}</td>`;
        html += "</tr>\n";
        i++;
      }
      html += "</tbody></table>\n";
      continue;
    }

    // Paragraph
    closeList();
    const pLines = [];
    while (i < lines.length && !/^\s*$/.test(lines[i]) && !/^#{1,6}\s/.test(lines[i]) && !/^```/.test(lines[i]) && !/^[-*_]{3,}\s*$/.test(lines[i]) && !/^>\s?/.test(lines[i]) && !/^[-*+]\s+/.test(lines[i]) && !/^\d+\.\s+/.test(lines[i])) {
      pLines.push(lines[i]);
      i++;
    }
    html += `<p>${inline(pLines.join(" "))}</p>\n`;
  }

  closeList();
  return html;
}

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
    const res = await fetch("index.md");
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    let src = await res.text();
    src = await resolveIncludes(src);
    const html = md(src);
    contentEl.innerHTML = html;
    navEl.innerHTML = buildNav(html);
    initScrollSpy();
  } catch (e) {
    contentEl.innerHTML = `<p>Failed to load documentation: ${e.message}</p>`;
  }
}

init();
