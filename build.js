/**
 * Drink Build Script
 * By: Chris Siena (Chris221)
 *
 * Zips the Drink/ addon folder into build/Drink_v<version>.zip and writes
 * build/release.json (the release manifest addon managers read from GitHub releases).
 *
 * Only Drink/ goes in the zip: tests, docs, tools and the repo files stay out.
 * Entries always use forward slashes, and macOS clutter (.DS_Store, __MACOSX) is skipped.
 */
const JSZip = require('jszip');
const path = require('path');
const fs = require('fs');

const ADDON = 'Drink';
const root = __dirname;
const addonDir = path.join(root, ADDON);
const tocFile = path.join(addonDir, `${ADDON}.toc`);
const outDir = path.join(root, 'build');

const SKIP = new Set(['.DS_Store', '__MACOSX', 'Thumbs.db', 'desktop.ini']);

//Addon Data
const toc = fs.readFileSync(tocFile, 'utf8');
const versionMatch = toc.match(/^## Version:\s*([0-9.]+)\s*$/m);
if (!versionMatch) throw new Error(`No "## Version:" line in ${tocFile}`);
const version = versionMatch[1];

const interfaceMatch = toc.match(/^## Interface:\s*([0-9,\s]+?)\s*$/m);
if (!interfaceMatch) throw new Error(`No "## Interface:" line in ${tocFile}`);
const interfaces = interfaceMatch[1].split(',').map(x => parseInt(x.trim(), 10)).filter(Number.isFinite);

// One TOC covers every client, so the flavor comes from the interface number itself.
function flavorFor(iface) {
  if (iface >= 16000 && iface < 17000) return 'forever';
  if (iface >= 10000 && iface < 20000) return 'classic';
  if (iface >= 20000 && iface < 30000) return 'bcc';
  if (iface >= 38000 && iface < 39000) return 'titan';
  if (iface >= 30000 && iface < 40000) return 'wrath';
  if (iface >= 40000 && iface < 50000) return 'cata';
  if (iface >= 50000 && iface < 60000) return 'mists';
  if (iface >= 100000) return 'mainline';
  throw new Error(`No release flavor for Interface ${iface}`);
}

const fileName = `${ADDON}_v${version}.zip`;

//For release
const releaseData = {
  releases: [
    {
      name: ADDON,
      version: `v${version}`,
      filename: fileName,
      nolib: false,
      metadata: interfaces
        .sort((a, b) => a - b)
        .map(iface => ({ flavor: flavorFor(iface), interface: iface })),
    },
  ],
};

//Script - Zip
function addFolder(zip, dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      addFolder(zip, full);
    } else if (entry.isFile()) {
      const rel = path.relative(root, full).split(path.sep).join('/');
      zip.file(rel, fs.readFileSync(full));
    }
  }
}

async function main() {
  const zip = new JSZip();
  addFolder(zip, addonDir);

  const count = Object.values(zip.files).filter(f => !f.dir).length;
  console.log(`Found ${count} files under ${ADDON}/`);

  fs.mkdirSync(outDir, { recursive: true });

  const data = await zip.generateAsync({
    type: 'nodebuffer',
    compression: 'DEFLATE',
    compressionOptions: { level: 9 },
  });
  fs.writeFileSync(path.join(outDir, fileName), data);
  console.log(`${fileName} saved!`);

  fs.writeFileSync(path.join(outDir, 'release.json'), JSON.stringify(releaseData, null, 2) + '\n');
  console.log('release.json saved!');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
