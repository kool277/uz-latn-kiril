#!/usr/bin/env node
/* Serves the production build like GitHub Pages does (static files, correct MIME types, no special headers):
 *   node scripts/serve.mjs [port] [base]      → http://localhost:4300/ (base e.g. /uz-latn-kiril/ like a project site) */
import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { dirname, extname, join, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'dist', 'uztranslit-web', 'browser');
const port = Number(process.argv[2] || process.env.PORT || 4300);
const base = process.argv[3] || '/';
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.wasm': 'application/wasm',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon', '.xml': 'application/xml', '.txt': 'text/plain; charset=utf-8',
  '.bas': 'text/plain; charset=utf-8', '.oxt': 'application/vnd.openofficeorg.extension'
};

createServer((req, res) => {
  const url = decodeURIComponent(new URL(req.url ?? '/', 'http://x').pathname);
  if (!url.startsWith(base)) { res.writeHead(404, { 'content-type': 'text/plain' }).end('not found'); return; }
  const path = '/' + url.slice(base.length);
  let file = normalize(join(root, path));
  if (!file.startsWith(root + sep) && file !== root) { res.writeHead(403).end(); return; }
  if (existsSync(file) && statSync(file).isDirectory()) file = join(file, 'index.html');
  if (!existsSync(file)) { res.writeHead(404, { 'content-type': 'text/plain' }).end('not found'); return; }
  res.writeHead(200, { 'content-type': MIME[extname(file)] ?? 'application/octet-stream', 'cache-control': 'no-cache' });
  createReadStream(file).pipe(res);
}).listen(port, () => console.log(`serving ${root} on http://localhost:${port}${base}`));
