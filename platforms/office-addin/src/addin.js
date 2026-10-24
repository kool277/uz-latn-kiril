/* UzTranslit Office add-in: the conversion for Word, Excel and PowerPoint through Office.js, and a plain-text
 * fallback for hosts without the newer APIs. ES5 on purpose: Office 2016 and 2019 on Windows may run task panes
 * in Internet Explorer 11. The host namespaces (Word, Excel, PowerPoint, Office) are parameters, so
 * test/run.mjs drives this file with fakes.
 *
 * Text is converted word by word: a run of non-whitespace characters is converted on its own and replaced only
 * when it changes. No conversion rule looks across whitespace, so the result is exactly the conversion of the
 * whole text (test/run.mjs checks this on the differential corpus), and every word keeps its formatting. A word
 * whose letters are formatted differently takes the formatting of its first letter: Office.js has no access to
 * runs inside a word (the VBA macros keep that too). */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory;
  else root.UzAddin = factory(root.UzTranslit);
})(this, function (UzTranslit) {
  'use strict';

  var SPACE = /[\t\n\v\f\r \u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]/;
  var BATCH = 300;                                       // paragraphs or shapes per round trip to the host

  // ---------------------------------------------------------------- text
  /** Runs of non-whitespace characters: [{start, end}] */
  function words(text) {
    var out = [], i = 0, n = text.length, s;
    while (i < n) {
      while (i < n && SPACE.test(text.charAt(i))) i++;
      if (i >= n) break;
      s = i;
      while (i < n && !SPACE.test(text.charAt(i))) i++;
      out.push({ start: s, end: i });
    }
    return out;
  }

  /** The words of text that change: [{start, length, text}], last first (so replacing them in order keeps the
   *  earlier positions valid) */
  function changes(text, from, to, options) {
    var out = [], ws = words(text), i, w, s, c;
    for (i = ws.length - 1; i >= 0; i--) {
      w = ws[i];
      s = text.substring(w.start, w.end);
      c = UzTranslit.convert(s, from, to, options);
      if (c !== s) out.push({ start: w.start, length: w.end - w.start, text: c });
    }
    return out;
  }

  /** The text with the changes applied (what the host shows afterwards) */
  function apply(text, list) {
    for (var i = 0; i < list.length; i++) text = text.substring(0, list[i].start) + list[i].text + text.substring(list[i].start + list[i].length);
    return text;
  }

  /** "auto" becomes the script the sample is written in */
  function resolve(from, sample) {
    return from === 'auto' ? UzTranslit.detect(sample) : from;
  }

  /** Excel would read a value like "=A1", "Mar 5", "1e5" or "TRUE" as a formula, date, number or logical: such a
   *  value gets the apostrophe prefix, which keeps it text and is not part of it */
  function excelText(s) {
    var t = s.replace(/^\s+|\s+$/g, '');
    if (/^[=+\-@]/.test(s)) return "'" + s;
    if (t !== '' && (!isNaN(Number(t.replace(/,/g, '.'))) || /^[-+]?[\d.,]+\s*%$/.test(t) || /^(true|false)$/i.test(t) ||
        /^\d{1,4}[./\-]\d{1,2}([./\-]\d{1,4})?$/.test(t) || /^\d{1,2}:\d{2}/.test(t) ||
        /^\d{1,2}[ \-]?[A-Za-z]{3,9}([ \-]\d{2,4})?$/.test(t) || /^[A-Za-z]{3,9}[ \-]?\d{1,2}(,?\s*\d{2,4})?$/.test(t))) return "'" + s;
    return s;
  }

  // ---------------------------------------------------------------- helpers
  function supported(Office, set, version) {
    try { return !!(Office && Office.context && Office.context.requirements && Office.context.requirements.isSetSupported(set, version)); }
    catch (e) { return false; }
  }

  /** runs fn(item, index) for every item, one sync per batch, in order */
  function batched(ctx, items, size, fn) {
    var i = 0;
    function next() {
      if (i >= items.length) return null;
      var end = Math.min(i + size, items.length);
      for (; i < end; i++) fn(items[i], i);
      return ctx.sync().then(next);
    }
    return ctx.sync().then(next);
  }

  /** like batched, but a batch the host rejects (a shape without text in it, say) is retried one item at a time,
   *  skipping the items that fail */
  function tolerant(ctx, items, size, fn) {
    var i = 0;
    function one(k) {
      return function () {
        try { fn(items[k], k); } catch (e) { return null; }
        return ctx.sync().then(null, function () { return null; });
      };
    }
    function next() {
      if (i >= items.length) return null;
      var from = i, end = Math.min(i + size, items.length);
      for (; i < end; i++) fn(items[i], i);
      return ctx.sync().then(next, function () {
        var p = ctx.sync().then(null, function () { return null; });
        for (var k = from; k < end; k++) p = p.then(one(k));
        return p.then(next);
      });
    }
    return ctx.sync().then(next);
  }

  // ---------------------------------------------------------------- Word
  /** o: {from, to, options, selection: bool}. Resolves to {from, words: n} */
  function word(Word, Office, o) {
    return Word.run(function (ctx) {
      var doc = ctx.document, sel = doc.getSelection(), body = doc.body;
      var tracking = supported(Office, 'WordApi', '1.4'), trackWas = null;
      var result = { from: o.from, words: 0 };
      sel.load('text');
      body.load('text');
      if (tracking) doc.load('changeTrackingMode');
      var parts = [], from;
      return ctx.sync().then(function () {
        var useSel = o.selection && /\S/.test(sel.text || '');
        from = result.from = resolve(o.from, (useSel ? sel.text : body.text).slice(0, 200000));
        if (from === o.to) return null;
        if (tracking && doc.changeTrackingMode !== 'Off') { trackWas = doc.changeTrackingMode; doc.changeTrackingMode = 'Off'; }
        // paragraphs: their ranges never cover a paragraph mark, so a replacement cannot merge two paragraphs
        var sections = useSel ? null : doc.sections;
        if (useSel) parts.push({ paras: sel.paragraphs, clip: sel });
        else {
          parts.push({ paras: body.paragraphs });
          sections.load('items');
        }
        return ctx.sync().then(function () {
          if (!useSel) {
            for (var i = 0; i < sections.items.length; i++) {
              var s = sections.items[i], kinds = ['Primary', 'FirstPage', 'EvenPages'];
              for (var k = 0; k < kinds.length; k++) {
                parts.push({ paras: s.getHeader(kinds[k]).paragraphs });
                parts.push({ paras: s.getFooter(kinds[k]).paragraphs });
              }
            }
          }
          for (var j = 0; j < parts.length; j++) parts[j].paras.load('items');
          return ctx.sync();
        }).then(function () {
          var all = [];
          for (var j = 0; j < parts.length; j++) {
            for (var p = 0; p < parts[j].paras.items.length; p++) all.push({ para: parts[j].paras.items[p], clip: parts[j].clip });
          }
          var ranges = [];
          return batched(ctx, all, BATCH, function (item) {
            var r = item.clip ? item.para.getRange('Whole').intersectWithOrNullObject(item.clip) : item.para.getRange('Whole');
            var w = r.getTextRanges([' '], false);
            r.load('text');                              // isNullObject is known once the range is loaded
            w.load('items/text');
            ranges.push({ r: r, w: w });
          }).then(function () {
            return batched(ctx, ranges, BATCH, function (x) {
              if (x.r.isNullObject) return;
              for (var i = 0; i < x.w.items.length; i++) {
                var t = x.w.items[i].text, c = UzTranslit.convert(t, from, o.to, o.options);
                if (c !== t) { x.w.items[i].insertText(c, 'Replace'); result.words++; }
              }
            });
          });
        });
      }).then(function () {
        if (trackWas) { doc.changeTrackingMode = trackWas; return ctx.sync(); }
      }, function (e) {
        if (trackWas) { doc.changeTrackingMode = trackWas; return ctx.sync().then(function () { throw e; }); }
        throw e;
      }).then(function () { return result; });
    });
  }

  // ---------------------------------------------------------------- Excel
  /** text constants of the selection or of every sheet; formulas, numbers and dates stay. Resolves to {from, cells} */
  function excel(Excel, Office, o) {
    return Excel.run(function (ctx) {
      var wb = ctx.workbook, ranges = [], result = { from: o.from, cells: 0 };
      var nullable = supported(Office, 'ExcelApi', '1.4');
      var start;
      if (o.selection) {
        var sel = wb.getSelectedRange();
        // a whole selected column has a million cells: only the used part counts
        var used = nullable ? sel.worksheet.getUsedRangeOrNullObject(true) : null;
        if (used) used.load('address');
        ranges.push({ r: sel, used: used });
        start = ctx.sync().then(function () {
          if (used) ranges[0].r = used.isNullObject ? used : sel.getIntersectionOrNullObject(used);
        });
      } else {
        var sheets = wb.worksheets;
        sheets.load('items');
        start = ctx.sync().then(function () {
          for (var i = 0; i < sheets.items.length; i++) {
            var ws = sheets.items[i];
            ranges.push({ r: nullable ? ws.getUsedRangeOrNullObject(true) : ws.getUsedRange(true) });
          }
        });
      }
      return start.then(function () {
        for (var i = 0; i < ranges.length; i++) ranges[i].r.load('address');   // isNullObject is known once loaded
        return ctx.sync();
      }).then(function () {
        for (var i = 0; i < ranges.length; i++) if (!ranges[i].r.isNullObject) ranges[i].r.load('formulas,values');
        return ctx.sync();
      }).then(function () {
        var sample = '', i, r, c, v;
        for (i = 0; i < ranges.length && sample.length < 200000; i++) {
          if (ranges[i].r.isNullObject) continue;
          v = ranges[i].r.values;
          for (r = 0; r < v.length && sample.length < 200000; r++) {
            for (c = 0; c < v[r].length; c++) if (typeof v[r][c] === 'string') sample += v[r][c] + '\n';
          }
        }
        var from = result.from = resolve(o.from, sample);
        if (from === o.to) return result;
        var writes = 0;
        for (i = 0; i < ranges.length; i++) {
          var rg = ranges[i].r;
          if (rg.isNullObject) continue;
          for (r = 0; r < rg.values.length; r++) {
            for (c = 0; c < rg.values[r].length; c++) {
              v = rg.values[r][c];
              if (typeof v !== 'string' || v === '' || String(rg.formulas[r][c]).charAt(0) === '=') continue;
              var conv = UzTranslit.convert(v, from, o.to, o.options);
              if (conv === v) continue;
              rg.getCell(r, c).values = [[excelText(conv)]];
              result.cells++;
              writes++;
            }
          }
        }
        return (writes ? ctx.sync() : null);
      }).then(function () { return result; });
    });
  }

  // ---------------------------------------------------------------- PowerPoint
  var PPT_TEXT = { GeometricShape: 1, TextBox: 1, Placeholder: 1 };

  /** every slide's text shapes (or the selected shapes), word by word. Resolves to {from, words} */
  function powerpoint(PowerPoint, Office, o) {
    return PowerPoint.run(function (ctx) {
      var result = { from: o.from, words: 0 }, shapes = [], slides = ctx.presentation.slides;
      var start;
      if (o.selection && supported(Office, 'PowerPointApi', '1.5')) {
        var picked = ctx.presentation.getSelectedShapes();
        picked.load('items/type');
        start = ctx.sync().then(function () { shapes = picked.items.slice(0); });
      } else {
        slides.load('items');
        start = ctx.sync().then(function () {
          var lists = [];
          for (var i = 0; i < slides.items.length; i++) { lists.push(slides.items[i].shapes); lists[i].load('items/type'); }
          return ctx.sync().then(function () {
            for (var j = 0; j < lists.length; j++) shapes = shapes.concat(lists[j].items);
          });
        });
      }
      var texts = [];
      return start.then(function () {
        shapes = shapes.filter(function (s) { return PPT_TEXT[s.type]; });
        var loaded = [];
        return tolerant(ctx, shapes, BATCH, function (s) {
          var tr = s.textFrame.textRange;
          tr.load('text');
          loaded.push({ shape: s, tr: tr });
        }).then(function () {
          for (var i = 0; i < loaded.length; i++) {      // what a failed batch left unloaded is skipped
            try { if (typeof loaded[i].tr.text === 'string') texts.push(loaded[i]); } catch (e) { /* not loaded */ }
          }
        });
      }).then(function () {
        var sample = '';
        for (var i = 0; i < texts.length && sample.length < 200000; i++) sample += texts[i].tr.text + '\n';
        var from = result.from = resolve(o.from, sample);
        if (from === o.to) return null;
        return batched(ctx, texts, BATCH, function (x) {
          var list = changes(x.tr.text || '', from, o.to, o.options);
          if (!list.length) return;
          result.words += list.length;
          for (var k = 0; k < list.length; k++) x.shape.textFrame.textRange.getSubstring(list[k].start, list[k].length).text = list[k].text;
        });
      }).then(function () { return result; });
    });
  }

  // ---------------------------------------------------------------- any host: the selected text, plain
  function selectedText(Office, o) {
    function call(fn, args) {
      return new (typeof Promise !== 'undefined' ? Promise : Office.Promise)(function (ok, fail) {
        fn.apply(Office.context.document, args.concat([function (r) {
          if (r.status === Office.AsyncResultStatus.Succeeded) ok(r.value); else fail(r.error);
        }]));
      });
    }
    var result = { from: o.from, words: 0, plain: true };   // plain: the selection only, without formatting
    return call(Office.context.document.getSelectedDataAsync, [Office.CoercionType.Text]).then(function (text) {
      text = text || '';
      var from = result.from = resolve(o.from, text);
      if (from === o.to) return result;
      var list = changes(text, from, o.to, o.options);
      result.words = list.length;
      if (!list.length) return result;
      return call(Office.context.document.setSelectedDataAsync, [apply(text, list), { coercionType: Office.CoercionType.Text }]).then(function () { return result; });
    });
  }

  /** the conversion for the current host */
  function run(hosts, o) {
    var Office = hosts.Office, h = Office.context.host, H = Office.HostType;
    if (h === H.Word && hosts.Word && supported(Office, 'WordApi', '1.3')) return word(hosts.Word, Office, o);
    if (h === H.Excel && hosts.Excel && supported(Office, 'ExcelApi', '1.1')) return excel(hosts.Excel, Office, o);
    if (h === H.PowerPoint && hosts.PowerPoint && supported(Office, 'PowerPointApi', '1.4')) return powerpoint(hosts.PowerPoint, Office, o);
    return selectedText(Office, o);
  }

  return {
    words: words, changes: changes, apply: apply, resolve: resolve, excelText: excelText,
    word: word, excel: excel, powerpoint: powerpoint, selectedText: selectedText, run: run
  };
});
