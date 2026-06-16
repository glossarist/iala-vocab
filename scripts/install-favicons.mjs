#!/usr/bin/env node
/**
 * install-favicons.mjs — Install RealFaviconGenerator (RFG) output over
 * concept-browser's defaults.
 *
 * Why this exists:
 *   concept-browser's built-in `favicons`-based generator produces a different
 *   file set than RFG and uses the package's "G" default favicon when no
 *   `branding.favicon`/`branding.logo.localPath` is configured. It also
 *   overwrites `public/favicon.svg` with that default during every build.
 *
 * This script runs AFTER `npx concept-browser build` and:
 *   1. Restores canonical RFG files from `assets/favicons/` to `public/` and
 *      `dist/` (overwriting concept-browser's defaults).
 *   2. Rewrites `site.webmanifest` with the correct BASE_PATH for icon URLs.
 *   3. Writes the canonical `favicon-links.html` markup.
 *   4. Strips concept-browser's auto-generated PNG/ICO cruft.
 *   5. Patches `dist/index.html`: removes CLI-injected <link> tags and injects
 *      our markup.
 *
 * The RFG favicon.svg contains a `@media (prefers-color-scheme: dark)` rule
 * that swaps between embedded light/dark icons, so a single SVG handles both
 * browser-tab themes.
 *
 * BASE_PATH expects the deployed subpath, e.g. "/iala-vocab/". Defaults to "/".
 */

import fs from 'fs';
import path from 'path';

const BASE_PATH = (process.env.BASE_PATH || '/').replace(/\/+$/, '') || '';
const ROOT = process.cwd();
const ASSETS_DIR = path.resolve(ROOT, 'assets', 'favicons');
const PUBLIC_DIR = path.resolve(ROOT, 'public');
const DIST_DIR = path.resolve(ROOT, 'dist');

// RealFaviconGenerator markup (matches what RFG's "install" instructions show).
const p = BASE_PATH;
const FAVICON_HTML = [
  `<link rel="icon" type="image/png" href="${p}/favicon-96x96.png" sizes="96x96" />`,
  `<link rel="icon" type="image/svg+xml" href="${p}/favicon.svg" />`,
  `<link rel="shortcut icon" href="${p}/favicon.ico" />`,
  `<link rel="apple-touch-icon" sizes="180x180" href="${p}/apple-touch-icon.png" />`,
  `<link rel="manifest" href="${p}/site.webmanifest" />`,
].join('\n    ');

// Canonical RFG files (kept in assets/favicons/, never touched by concept-browser).
const KEEP_FILES = [
  'favicon.svg',
  'favicon-96x96.png',
  'favicon.ico',
  'apple-touch-icon.png',
  'web-app-manifest-192x192.png',
  'web-app-manifest-512x512.png',
];

// concept-browser cruft to delete.
const CRUFT_FILES = [
  'apple-touch-icon-57x57.png',
  'apple-touch-icon-60x60.png',
  'apple-touch-icon-72x72.png',
  'apple-touch-icon-76x76.png',
  'apple-touch-icon-114x114.png',
  'apple-touch-icon-120x120.png',
  'apple-touch-icon-144x144.png',
  'apple-touch-icon-152x152.png',
  'apple-touch-icon-167x167.png',
  'apple-touch-icon-180x180.png',
  'apple-touch-icon-1024x1024.png',
  'apple-touch-icon-precomposed.png',
  'favicon-16x16.png',
  'favicon-32x32.png',
  'favicon-48x48.png',
  'browserconfig.xml',
];

function siteWebmanifestContent() {
  // Build webmanifest with correct BASE_PATH. Keeps URLs portable across
  // deployments (e.g. local "/" vs GitHub Pages "/iala-vocab/").
  return JSON.stringify({
    name: 'IALA Dictionary',
    short_name: 'IALA Dict',
    icons: [
      {
        src: `${p}/web-app-manifest-192x192.png`,
        sizes: '192x192',
        type: 'image/png',
        purpose: 'maskable',
      },
      {
        src: `${p}/web-app-manifest-512x512.png`,
        sizes: '512x512',
        type: 'image/png',
        purpose: 'maskable',
      },
    ],
    theme_color: '#003366',
    background_color: '#ffffff',
    display: 'standalone',
    start_url: `${p}/`,
  }, null, 2) + '\n';
}

function rm(targetDir, file) {
  const fp = path.join(targetDir, file);
  if (fs.existsSync(fp)) {
    fs.unlinkSync(fp);
    return true;
  }
  return false;
}

function applyFaviconsToDir(targetDir, label) {
  if (!fs.existsSync(targetDir)) return;
  console.log(`\n=== ${label}: ${targetDir} ===`);

  // 1. Restore canonical files from assets/favicons/.
  for (const f of KEEP_FILES) {
    const src = path.join(ASSETS_DIR, f);
    if (!fs.existsSync(src)) {
      console.warn(`  ! missing canonical: ${src}`);
      continue;
    }
    fs.copyFileSync(src, path.join(targetDir, f));
  }

  // 2. Write site.webmanifest with BASE_PATH.
  fs.writeFileSync(path.join(targetDir, 'site.webmanifest'), siteWebmanifestContent());

  // 3. Remove concept-browser cruft.
  for (const f of CRUFT_FILES) {
    if (rm(targetDir, f)) console.log(`  - removed ${f}`);
  }
}

function writeFaviconLinksHtml() {
  // Used by Vite as the source of <head> favicon links during dev mode.
  fs.writeFileSync(path.join(PUBLIC_DIR, 'favicon-links.html'), FAVICON_HTML + '\n');
  console.log(`\n=== public/favicon-links.html ===\n  wrote RFG markup`);
}

function patchDistIndex() {
  const indexPath = path.join(DIST_DIR, 'index.html');
  if (!fs.existsSync(indexPath)) {
    console.warn(`\n! dist/index.html not found; skipping HTML patch`);
    return;
  }
  console.log(`\n=== patching dist/index.html ===`);
  let html = fs.readFileSync(indexPath, 'utf8');

  // Strip ALL existing favicon-related <link> tags so we don't duplicate.
  const before = html.length;
  html = html.replace(
    /<link[^>]*\brel=["'](icon|apple-touch-icon|apple-touch-icon-precomposed|manifest|shortcut icon)["'][^>]*>\s*/gi,
    ''
  );
  console.log(`  stripped ${before - html.length} bytes of old favicon markup`);

  // Inject our markup right after the opening <head>.
  if (/<head[^>]*>/i.test(html)) {
    html = html.replace(/<head([^>]*)>/i, `<head$1>\n    ${FAVICON_HTML}\n  `);
    console.log(`  injected RFG markup`);
  } else {
    console.warn(`  ! no <head> tag found`);
  }

  fs.writeFileSync(indexPath, html);
}

if (!fs.existsSync(ASSETS_DIR)) {
  console.error(`! canonical assets missing: ${ASSETS_DIR}`);
  process.exit(1);
}

console.log(`BASE_PATH = "${p || '/'}"`);
applyFaviconsToDir(PUBLIC_DIR, 'public');
applyFaviconsToDir(DIST_DIR, 'dist');
writeFaviconLinksHtml();
patchDistIndex();
console.log('\nFavicons installed.');
