#!/usr/bin/env node
/* Renders the PWA icons and the Open Graph preview image with Playwright's Chromium:
 *   node scripts/make-images.mjs   → public/icons/icon-*.png, public/icons/maskable-512x512.png, public/og-image.png
 * The PNGs are committed; run this again only when the design changes. */
import { chromium } from '@playwright/test';
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const pub = join(dirname(fileURLToPath(import.meta.url)), '..', 'public');
mkdirSync(join(pub, 'icons'), { recursive: true });
const SERIF = "Georgia, 'DejaVu Serif', 'Liberation Serif', serif";

const icon = (size, maskable) => `<!doctype html><html><body style="margin:0;background:transparent">
<div style="width:${size}px;height:${size}px;display:flex;align-items:center;justify-content:center;background:#0f766e;
border-radius:${maskable ? 0 : size * 0.22}px;color:#fff;font:700 ${size * (maskable ? 0.42 : 0.56)}px/1 ${SERIF};padding-top:${size * 0.04}px;box-sizing:border-box">Ö</div>
</body></html>`;

const og = `<!doctype html><html><body style="margin:0">
<div style="width:1200px;height:630px;box-sizing:border-box;padding:72px 80px;background:#f6f3ee;color:#1c1917;font-family:'Segoe UI',system-ui,'DejaVu Sans',sans-serif;display:flex;flex-direction:column;justify-content:space-between">
  <div style="display:flex;align-items:center;gap:28px">
    <div style="width:120px;height:120px;border-radius:28px;background:#0f766e;color:#fff;display:flex;align-items:center;justify-content:center;font:700 72px/1 ${SERIF}">Ö</div>
    <div>
      <div style="font:700 56px/1.1 ${SERIF};white-space:nowrap"><span style="color:#0f766e">Lotin</span> · Kirill · Yangi lotin</div>
      <div style="font-size:30px;color:#6b6560;margin-top:10px">Oʻzbek alifbo konvertori — OʻRQ-1184 (Ö Ğ Ş Ç)</div>
    </div>
  </div>
  <div style="font:400 44px/1.4 ${SERIF}">Oʻzbekiston <span style="color:#0f766e">→</span> Özbekiston <span style="color:#0f766e">→</span> Ўзбекистон</div>
  <div style="display:flex;justify-content:space-between;align-items:flex-end;gap:24px;font-size:25px;line-height:1.45;color:#6b6560">
    <div>Matn va hujjatlar: Word · Excel · PowerPoint · LibreOffice · RTF · EPUB<br>Formatlash saqlanadi · brauzerda, oflayn · WebAssembly</div>
    <div style="font-weight:600;color:#0f766e">latin.jaybi.uz</div>
  </div>
</div></body></html>`;

const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 1 });
for (const size of [72, 96, 128, 144, 152, 192, 384, 512]) {
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(icon(size, false));
  await page.screenshot({ path: join(pub, 'icons', `icon-${size}x${size}.png`), omitBackground: true });
}
await page.setViewportSize({ width: 512, height: 512 });
await page.setContent(icon(512, true));
await page.screenshot({ path: join(pub, 'icons', 'maskable-512x512.png') });
await page.setViewportSize({ width: 1200, height: 630 });
await page.setContent(og);
await page.screenshot({ path: join(pub, 'og-image.png') });
await browser.close();
console.log('wrote icons and og-image.png');
