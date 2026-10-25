#!/usr/bin/env node
/* Post-build: one crawlable page per search language — / (Uzbek), /ru/, /en/ — each with its own title, description,
 * keywords, canonical URL, hreflang links, Open Graph tags, JSON-LD (WebApplication + FAQPage) and a static text
 * inside <app-root> that search engines read without running JavaScript (Angular replaces it on start). The app
 * picks its language from the path (settings.service.ts). Title and description come from the i18n tables, so the
 * static page and the running app agree. Runs after `ng build`, before csp-hash.mjs. */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const web = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(web, 'dist', 'uztranslit-web', 'browser');
const SITE = 'https://latin.jaybi.uz/';

/** 'doc.title' and 'doc.description' of src/app/i18n/<file>.ts */
function messages(file) {
  const src = readFileSync(join(web, 'src', 'app', 'i18n', file), 'utf8');
  const get = key => {
    const m = new RegExp(`'${key.replace('.', '\\.')}': '([^'\\n]*)'`).exec(src);
    if (!m) throw new Error(`seo: ${key} not found in ${file}`);
    return m[1];
  };
  return { title: get('doc.title'), description: get('doc.description') };
}

const FORMATS = 'DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF, EPUB, FB2, HTML, Markdown, JSON, XML, SVG, CSV, TXT, SRT, VTT, ASS';

const PAGES = [
  {
    lang: 'uz', path: '', htmlLang: 'uz-Latn', hreflang: 'uz', ogLocale: 'uz_UZ', i18n: 'uz.ts', switchName: 'Oʻzbekcha',
    keywords: 'kirill lotin, lotin kirill, kirilldan lotinga, lotindan kirillga, kirill lotin oʻgirgich, kirill lotin konvertor, ' +
      'lotincha kirillcha, oʻzbek alifbosi, yangi oʻzbek alifbosi 2026, yangi lotin alifbosi, Ö Ğ Ş Ç, OʻRQ-1184, ' +
      'transliteratsiya, Word kirill lotin, Excel kirill lotin, кирилл лотин, лотин кирилл, кириллдан лотинга, ' +
      'кирилл лотин ўгиргич, ўзбек алифбоси',
    h1: 'Kirill ↔ lotin oʻgirgich: oʻzbek matni va hujjatlari uchun',
    intro: 'Oʻzbek matnini kirilldan lotinga, lotindan kirillga yoki 2026-yilgi yangi lotin alifbosiga (Ö Ğ Ş Ç, ' +
      'OʻRQ-1184) bir zumda oʻgiring. Word, Excel, PowerPoint va boshqa fayllar formatlashi, jadvallari va rasmlari ' +
      'bilan oʻgiriladi. Hammasi brauzerda ishlaydi: matn va fayllar hech qayerga yuborilmaydi.',
    featuresTitle: 'Imkoniyatlar',
    features: [
      'Kirill → lotin, lotin → kirill va ikkalasidan yangi lotinga (Ö Ğ Ş Ç); alifbo avtomatik aniqlanadi.',
      'Oʻ, gʻ, sh, ch, ts, ye, yo, yu, ya, tutuq belgisi (ʼ) va oʻzlashma soʻzlar (obyekt → объект, sirk → цирк) qoidaga koʻra.',
      `Fayllar formatlashni buzmasdan: ${FORMATS}. Bir nechta faylni ZIP qilib yuklab olish mumkin.`,
      'Microsoft Office (Word, Excel, PowerPoint) va LibreOffice uchun qoʻshimchalar.',
      'Bepul, roʻyxatdan oʻtmasdan, sahifa bir marta ochilgach internetsiz ham ishlaydi.'
    ],
    faqTitle: 'Koʻp beriladigan savollar',
    faq: [
      ['Kirill yozuvidagi matnni lotinchaga qanday oʻgiraman?',
        'Matnni chap maydonga qoʻying, «Qaysi alifboga» boʻlimida «Lotin 1995» yoki «Yangi lotin»ni tanlang — natija ' +
        'darhol oʻng maydonda chiqadi. Hujjatni «Fayllar» boʻlimiga tashlang.'],
      ['Yangi oʻzbek lotin alifbosi (2026) nimasi bilan farq qiladi?',
        '2026-yil 21-oktabrdagi OʻRQ-1184-son qonunga koʻra oʻ, gʻ, sh, ch oʻrniga Ö, Ğ, Ş, Ç yoziladi: ' +
        'Oʻzbekiston → Özbekiston, shahar → şahar, choy → çoy.'],
      ['Word yoki Excel faylini formatlashini buzmasdan oʻgirsa boʻladimi?',
        'Ha. Faylni «Fayllar» boʻlimiga tashlang: faqat matn oʻzgaradi, shriftlar, jadvallar, rasmlar va uslublar ' +
        'oʻz holicha qoladi. Fayl kompyuteringizdan chiqmaydi.'],
      ['Xizmat pullimi?', 'Yoʻq, bepul va reklamasiz. Roʻyxatdan oʻtish shart emas.']
    ]
  },
  {
    lang: 'ru', path: 'ru/', htmlLang: 'ru', hreflang: 'ru', ogLocale: 'ru_RU', i18n: 'ru.ts', switchName: 'Русский',
    keywords: 'кириллица латиница, конвертер кириллицы в латиницу, узбекский с кириллицы на латиницу, ' +
      'перевод с кириллицы на латиницу узбекский, латиница в кириллицу узбекский, транслитерация узбекского, ' +
      'узбекский алфавит, новый узбекский алфавит 2026, новая латиница, Ö Ğ Ş Ç, ЗРУ-1184, ' +
      'конвертер Word кириллица латиница, kirill lotin, кирилл лотин',
    h1: 'Конвертер узбекского текста: кириллица ↔ латиница',
    intro: 'Переводите узбекский текст с кириллицы на латиницу, с латиницы на кириллицу или на новую латиницу ' +
      '2026 года (Ö Ğ Ş Ç, закон ЗРУ-1184) за секунду. Документы Word, Excel, PowerPoint и другие конвертируются ' +
      'с сохранением форматирования, таблиц и картинок. Всё работает в браузере: тексты и файлы никуда не отправляются.',
    featuresTitle: 'Возможности',
    features: [
      'Кириллица → латиница, латиница → кириллица и обе — в новую латиницу (Ö Ğ Ş Ç); алфавит определяется автоматически.',
      'Правила для oʻ, gʻ, sh, ch, ts, ye, yo, yu, ya, тутука (ʼ) и заимствований (obyekt → объект, sirk → цирк).',
      `Файлы без потери форматирования: ${FORMATS}. Несколько файлов можно скачать одним ZIP.`,
      'Надстройки для Microsoft Office (Word, Excel, PowerPoint) и LibreOffice.',
      'Бесплатно, без регистрации; после первого открытия работает без интернета.'
    ],
    faqTitle: 'Частые вопросы',
    faq: [
      ['Как перевести узбекский текст с кириллицы на латиницу?',
        'Вставьте текст в левое поле и выберите «Латиница 1995» или «Новая латиница» — результат сразу появится ' +
        'справа. Документ перетащите в раздел «Файлы».'],
      ['Чем отличается новый узбекский латинский алфавит 2026 года?',
        'По закону ЗРУ-1184 от 21 октября 2026 года вместо oʻ, gʻ, sh, ch пишутся Ö, Ğ, Ş, Ç: ' +
        'Oʻzbekiston → Özbekiston, shahar → şahar, choy → çoy.'],
      ['Можно ли конвертировать Word или Excel без потери форматирования?',
        'Да. Перетащите файл в раздел «Файлы»: меняется только текст, шрифты, таблицы, картинки и стили остаются ' +
        'прежними. Файл не покидает ваш компьютер.'],
      ['Это бесплатно?', 'Да, бесплатно и без рекламы. Регистрация не нужна.']
    ]
  },
  {
    lang: 'en', path: 'en/', htmlLang: 'en', hreflang: 'en', ogLocale: 'en_US', i18n: 'en.ts', switchName: 'English',
    keywords: 'Uzbek Cyrillic to Latin, Uzbek Latin to Cyrillic, Uzbek Cyrillic Latin converter, Uzbek transliteration, ' +
      'Uzbek alphabet converter, new Uzbek alphabet 2026, Uzbek Latin alphabet, Ö Ğ Ş Ç, ' +
      'convert Uzbek Word document to Latin, kirill lotin, кирилл лотин',
    h1: 'Uzbek Cyrillic ↔ Latin converter',
    intro: 'Convert Uzbek text from Cyrillic to Latin, from Latin to Cyrillic, or to the new Latin alphabet of 2026 ' +
      '(Ö Ğ Ş Ç, law OʻRQ-1184) in an instant. Word, Excel, PowerPoint and other documents keep their formatting, ' +
      'tables and pictures. Everything runs in your browser: text and files are never uploaded.',
    featuresTitle: 'Features',
    features: [
      'Cyrillic → Latin, Latin → Cyrillic, and either one to the new Latin alphabet (Ö Ğ Ş Ç); the script is detected automatically.',
      'Correct oʻ, gʻ, sh, ch, ts, ye, yo, yu, ya, the tutuq sign (ʼ) and loanwords (obyekt → объект, sirk → цирк).',
      `Documents without losing formatting: ${FORMATS}. Several files download as one ZIP.`,
      'Add-ins for Microsoft Office (Word, Excel, PowerPoint) and LibreOffice.',
      'Free, no sign-up; after the first visit it works offline.'
    ],
    faqTitle: 'Frequently asked questions',
    faq: [
      ['How do I convert Uzbek Cyrillic text to Latin?',
        'Paste the text into the left box and choose “Latin 1995” or “Latin 2026” — the result appears on the right ' +
        'at once. Drop documents on the “Files” section.'],
      ['What is different in the new Uzbek Latin alphabet of 2026?',
        'Under law OʻRQ-1184 of 21 October 2026, oʻ, gʻ, sh and ch are written Ö, Ğ, Ş and Ç: ' +
        'Oʻzbekiston → Özbekiston, shahar → şahar, choy → çoy.'],
      ['Can I convert a Word or Excel file without losing formatting?',
        'Yes. Drop the file on the “Files” section: only the text changes; fonts, tables, pictures and styles stay ' +
        'as they were. The file never leaves your computer.'],
      ['Is it free?', 'Yes, free and without ads. No sign-up is needed.']
    ]
  }
];

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const json = v => JSON.stringify(v).replace(/</g, '\\u003c');

function head(p, m) {
  const url = SITE + p.path;
  const ld = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'WebApplication', '@id': SITE + '#app', name: m.title, alternateName: ['UzTranslit', 'latin.jaybi.uz'],
        url, description: m.description, inLanguage: p.htmlLang, image: SITE + 'og-image.png',
        applicationCategory: 'UtilitiesApplication', operatingSystem: 'Windows, macOS, Linux, Android, iOS (web browser)',
        browserRequirements: 'JavaScript, WebAssembly', isAccessibleForFree: true,
        offers: { '@type': 'Offer', price: '0', priceCurrency: 'UZS' }, featureList: p.features
      },
      {
        '@type': 'FAQPage', inLanguage: p.htmlLang,
        mainEntity: p.faq.map(([q, a]) => ({ '@type': 'Question', name: q, acceptedAnswer: { '@type': 'Answer', text: a } }))
      }
    ]
  };
  return [
    `<title>${esc(m.title)}</title>`,
    `<meta name="description" content="${esc(m.description)}">`,
    `<meta name="keywords" content="${esc(p.keywords)}">`,
    `<meta name="robots" content="index, follow, max-image-preview:large">`,
    `<link rel="canonical" href="${url}">`,
    ...PAGES.map(o => `<link rel="alternate" hreflang="${o.hreflang}" href="${SITE + o.path}">`),
    `<link rel="alternate" hreflang="x-default" href="${SITE}">`,
    `<meta property="og:type" content="website">`,
    `<meta property="og:site_name" content="latin.jaybi.uz">`,
    `<meta property="og:url" content="${url}">`,
    `<meta property="og:title" content="${esc(m.title)}">`,
    `<meta property="og:description" content="${esc(m.description)}">`,
    `<meta property="og:image" content="${SITE}og-image.png">`,
    `<meta property="og:image:width" content="1200">`,
    `<meta property="og:image:height" content="630">`,
    `<meta property="og:locale" content="${p.ogLocale}">`,
    ...PAGES.filter(o => o !== p).map(o => `<meta property="og:locale:alternate" content="${o.ogLocale}">`),
    `<meta name="twitter:card" content="summary_large_image">`,
    `<meta name="twitter:title" content="${esc(m.title)}">`,
    `<meta name="twitter:description" content="${esc(m.description)}">`,
    `<meta name="twitter:image" content="${SITE}og-image.png">`,
    `<script type="application/ld+json">${json(ld)}</script>`
  ].map(l => '  ' + l).join('\n');
}

/** Static text for crawlers and for the moment before the app starts; links are relative to <base href>, so
 *  /<repo>/ works too. */
function body(p) {
  return `<app-root><main class="seo-static">
    <h1>${esc(p.h1)}</h1>
    <p>${esc(p.intro)}</p>
    <h2>${esc(p.featuresTitle)}</h2>
    <ul>${p.features.map(f => `<li>${esc(f)}</li>`).join('')}</ul>
    <h2>${esc(p.faqTitle)}</h2>
    ${p.faq.map(([q, a]) => `<h3>${esc(q)}</h3><p>${esc(a)}</p>`).join('\n    ')}
    <p>${PAGES.map(o => `<a href="${o.path || './'}" hreflang="${o.hreflang}" lang="${o.htmlLang}">${esc(o.switchName)}</a>`).join(' · ')}</p>
  </main></app-root>`;
}

const template = readFileSync(join(dist, 'index.html'), 'utf8');
const block = /[ \t]*<!-- seo -->[\s\S]*?<!-- \/seo -->/;
if (!block.test(template) || !template.includes('<app-root></app-root>')) throw new Error('seo: markers not found in index.html');

for (const p of PAGES) {
  const m = messages(p.i18n);
  const html = template
    .replace(/<html lang="[^"]*">/, `<html lang="${p.htmlLang}">`)
    .replace(block, () => head(p, m))
    .replace('<app-root></app-root>', () => body(p));
  mkdirSync(join(dist, p.path), { recursive: true });
  writeFileSync(join(dist, p.path, 'index.html'), html);
}
console.log(`seo: ${PAGES.map(p => '/' + p.path).join(' ')}`);
