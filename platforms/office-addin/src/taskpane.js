/* UzTranslit task pane: the form, its three languages and the call into addin.js. ES5 (Internet Explorer 11 runs
 * task panes in some Office 2016/2019 installations). */
(function () {
  'use strict';

  var T = {
    uz: {
      lead: 'Oʻzbek matni: Kirill ⇄ Lotin 1995 ⇄ Yangi lotin. Formatlash saqlanadi.',
      from: 'Manba yozuv', to: 'Natija yozuvi', auto: 'Avto (aniqlash)', cyr: 'Кирилл', lat: 'Lotin 1995', 'new': 'Yangi lotin',
      newLong: 'Yangi lotin (Ö Ğ Ş Ç)', where: 'Qayerda', selection: 'Belgilangan joy (boʻlmasa — butun hujjat)', document: 'Butun hujjat',
      ascii: "Oddiy apostrof (') ishlatilsin", go: 'Oʻgirish', working: 'Oʻgirilmoqda…',
      words: '{n} ta soʻz oʻgirildi ({from} → {to}).', cells: '{n} ta katak oʻgirildi ({from} → {to}).',
      plain: ' Bu Office versiyasida faqat belgilangan matn oʻgiriladi, formatlashsiz.',
      same: 'Matn allaqachon {to} yozuvida: oʻgiradigan narsa yoʻq.', none: 'Oʻgiradigan matn topilmadi.',
      error: 'Xato: {msg}', noOffice: 'Bu sahifa Word, Excel yoki PowerPoint ichida, UzTranslit qoʻshimchasi sifatida ochiladi.'
    },
    ru: {
      lead: 'Узбекский текст: кириллица ⇄ латиница 1995 ⇄ новая латиница. Форматирование сохраняется.',
      from: 'Исходный алфавит', to: 'Алфавит результата', auto: 'Авто (определить)', cyr: 'Кириллица', lat: 'Латиница 1995', 'new': 'Новая латиница',
      newLong: 'Новая латиница (Ö Ğ Ş Ç)', where: 'Где', selection: 'Выделение (если нет — весь документ)', document: 'Весь документ',
      ascii: "Простой апостроф (')", go: 'Преобразовать', working: 'Преобразование…',
      words: 'Преобразовано слов: {n} ({from} → {to}).', cells: 'Преобразовано ячеек: {n} ({from} → {to}).',
      plain: ' В этой версии Office преобразуется только выделенный текст, без форматирования.',
      same: 'Текст уже на алфавите «{to}»: преобразовывать нечего.', none: 'Текст для преобразования не найден.',
      error: 'Ошибка: {msg}', noOffice: 'Эта страница открывается внутри Word, Excel или PowerPoint как надстройка UzTranslit.'
    },
    en: {
      lead: 'Uzbek text: Cyrillic ⇄ Latin 1995 ⇄ new Latin. Formatting is kept.',
      from: 'From', to: 'To', auto: 'Auto (detect)', cyr: 'Cyrillic', lat: 'Latin 1995', 'new': 'New Latin',
      newLong: 'New Latin (Ö Ğ Ş Ç)', where: 'Where', selection: 'Selection (none: the whole document)', document: 'Whole document',
      ascii: "Plain apostrophe (')", go: 'Convert', working: 'Converting…',
      words: '{n} word(s) converted ({from} → {to}).', cells: '{n} cell(s) converted ({from} → {to}).',
      plain: ' This Office version converts the selected text only, without formatting.',
      same: 'The text is already in {to}: nothing to convert.', none: 'No text to convert was found.',
      error: 'Error: {msg}', noOffice: 'This page opens inside Word, Excel or PowerPoint as the UzTranslit add-in.'
    }
  };
  var lang = 'uz';

  function $(id) { return document.getElementById(id); }
  function t(key, vars) {
    var s = (T[lang] && T[lang][key]) || T.en[key] || key;
    for (var k in vars) if (vars.hasOwnProperty(k)) s = s.split('{' + k + '}').join(vars[k]);
    return s;
  }
  function store(key, value) {
    try {
      if (value === undefined) return window.localStorage.getItem('uztranslit.' + key);
      window.localStorage.setItem('uztranslit.' + key, value);
    } catch (e) { /* storage may be off in the host's web view */ }
    return null;
  }
  function render() {
    var els = document.querySelectorAll('[data-i18n]');
    for (var i = 0; i < els.length; i++) els[i].textContent = t(els[i].getAttribute('data-i18n'));
    document.documentElement.setAttribute('lang', lang);
    $('lang').value = lang;
  }
  function say(text, kind) {
    var el = $('status');
    el.textContent = text;
    el.className = kind || '';
  }
  function scriptName(s) { return t(s); }

  function convert() {
    var o = {
      from: $('from').value,
      to: $('to').value,
      selection: $('sel').checked,
      options: $('ascii').checked ? { okina: "'", tutuq: "'" } : {}
    };
    store('from', o.from); store('to', o.to); store('where', o.selection ? 'sel' : 'all'); store('ascii', $('ascii').checked ? '1' : '');
    $('go').disabled = true;
    say(t('working'));
    window.UzAddin.run({ Office: window.Office, Word: window.Word, Excel: window.Excel, PowerPoint: window.PowerPoint }, o).then(function (r) {
      $('go').disabled = false;
      var n = r.cells != null ? r.cells : r.words, names = { from: scriptName(r.from), to: scriptName(o.to) };
      if (r.from === o.to) say(t('same', names));
      else if (!n) say(t('none') + (r.plain ? t('plain') : ''));
      else say(t(r.cells != null ? 'cells' : 'words', { n: n, from: names.from, to: names.to }) + (r.plain ? t('plain') : ''), 'ok');
    }, function (e) {
      $('go').disabled = false;
      say(t('error', { msg: (e && (e.message || e.code)) || String(e) }), 'err');
    });
  }

  function start(displayLanguage) {
    var saved = store('lang'), dl = String(displayLanguage || navigator.language || '').toLowerCase();
    lang = T[saved] ? saved : (dl.indexOf('ru') === 0 ? 'ru' : 'uz');   // Uzbek first, as on latin.jaybi.uz
    render();
    if (store('from')) $('from').value = store('from');
    if (store('to')) $('to').value = store('to');
    if (store('where') === 'all') $('all').checked = true;
    $('ascii').checked = store('ascii') === '1';
    $('lang').onchange = function () { lang = $('lang').value; store('lang', lang); render(); };
    $('go').onclick = convert;
  }

  function ready() {
    start(window.Office && Office.context && Office.context.displayLanguage);
    if (window.Office && Office.context && Office.context.host) $('go').disabled = false;
    else say(t('noOffice'));
  }

  if (window.Office && Office.onReady) Office.onReady(ready);
  else if (window.Office) Office.initialize = ready;
  else if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready);
  else ready();
})();
