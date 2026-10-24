// Small stand-ins for the parts of Office.js the add-in uses. Strict where Office.js is: a property read before
// load() + sync() throws, writes happen in order, ranges follow the edits around them, a text replacement takes the
// formatting of its first character. Text is held as characters with a formatting tag each.

export class Ctx {
  constructor() { this.pending = []; this.syncs = 0; this.failNext = null; }
  sync() {
    this.syncs++;
    const pending = this.pending;
    this.pending = [];
    if (this.failNext && pending.some(this.failNext)) {
      this.failNext = null;
      return Promise.reject(new Error('GeneralException'));
    }
    for (const o of pending) o._loaded = true;
    return Promise.resolve();
  }
}

class Obj {
  constructor(ctx) { this._ctx = ctx; this._loaded = false; }
  load() { this._ctx.pending.push(this); return this; }
  _need(what) { if (!this._loaded) throw new Error(`PropertyNotLoaded: ${this.constructor.name}.${what}`); }
}

const chars = (s, f) => [...s].map(c => ({ c, f }));
const str = cs => cs.map(x => x.c).join('');

// ------------------------------------------------------------------ Word
class WParagraph {
  constructor(runs) { this.cs = runs.flatMap(([s, f]) => chars(s, f)); this.ranges = new Set(); }
  get text() { return str(this.cs); }
  replace(start, end, text) {
    const f = this.cs[start] ? this.cs[start].f : (this.cs[start - 1] || { f: null }).f;
    const delta = [...text].length - (end - start);
    this.cs.splice(start, end - start, ...chars(text, f));
    for (const r of this.ranges) {
      if (r.start >= end) r.start += delta;
      if (r.end >= end) r.end += delta;
    }
  }
}

class WRange extends Obj {
  constructor(ctx, para, start, end) { super(ctx); this.para = para; this.start = start; this.end = end; this.isNullObject = false; para.ranges.add(this); }
  get text() { this._need('text'); return str(this.para.cs.slice(this.start, this.end)); }
  intersectWithOrNullObject(other) {
    const s = Math.max(this.start, other.start), e = Math.min(this.end, other.end);
    if (other.para !== this.para && !(other.paras && other.paras.has(this.para))) return Object.assign(new WRange(this._ctx, this.para, 0, 0), { isNullObject: true });
    if (other.paras) { const lo = other.para === this.para ? other.start : 0; const hi = other.endPara === this.para ? other.endOffset : this.end; return new WRange(this._ctx, this.para, Math.max(this.start, lo), Math.min(this.end, hi)); }
    return e >= s ? new WRange(this._ctx, this.para, s, e) : Object.assign(new WRange(this._ctx, this.para, 0, 0), { isNullObject: true });
  }
  getTextRanges(marks, trim) {
    if (trim !== false || marks.length !== 1 || marks[0] !== ' ') throw new Error('fake supports getTextRanges([" "], false) only');
    const out = [];
    let s = this.start;
    for (let i = this.start; i < this.end; i++) {
      if (this.para.cs[i].c === ' ') { out.push(new WRange(this._ctx, this.para, s, i + 1)); s = i + 1; }
    }
    if (s < this.end) out.push(new WRange(this._ctx, this.para, s, this.end));
    return new Collection(this._ctx, out);
  }
  insertText(text, where) {
    if (where !== 'Replace') throw new Error('fake supports Replace only');
    const end = this.end;
    this.para.replace(this.start, end, text);
    this.end = this.start + [...text].length;
  }
}

class Collection extends Obj {
  constructor(ctx, items) { super(ctx); this._items = items; }
  get items() { this._need('items'); return this._items; }
  load(what) { super.load(); if (/^items\//.test(what || '')) for (const i of this._items) if (i.load) i.load(); return this; }
}

class WParagraphObj extends Obj {
  constructor(ctx, para) { super(ctx); this.para = para; }
  getRange() { return new WRange(this._ctx, this.para, 0, this.para.cs.length); }
}

class WBody extends Obj {
  constructor(ctx, paras) { super(ctx); this.paras = paras; }
  get text() { this._need('text'); return this.paras.map(p => p.text).join('\r'); }
  get paragraphs() { return new Collection(this._ctx, this.paras.map(p => new WParagraphObj(this._ctx, p))); }
}

class WSelection extends Obj {
  // from (para a, offset s) to (para b, offset e)
  constructor(ctx, all, a, s, b, e) {
    super(ctx);
    this.list = all.slice(all.indexOf(a), all.indexOf(b) + 1);
    this.paras = new Set(this.list); this.para = a; this.start = s; this.endPara = b; this.endOffset = e;
  }
  get text() {
    this._need('text');
    return this.list.map(p => str(p.cs.slice(p === this.para ? this.start : 0, p === this.endPara ? this.endOffset : p.cs.length))).join('\r');
  }
  get paragraphs() { return new Collection(this._ctx, this.list.map(p => new WParagraphObj(this._ctx, p))); }
}

export function fakeWord(model) {
  // model: {body: [[ [text, fmt], ... ], ...], headers: [...same], selection: [paraIndex, start, paraIndex, end] | null, tracking}
  const ctx = new Ctx();
  const body = model.body.map(r => new WParagraph(r));
  const header = (model.headers || []).map(r => new WParagraph(r));
  const empty = () => new WBody(ctx, []);
  const doc = new (class extends Obj {
    constructor() { super(ctx); this._mode = model.tracking || 'Off'; this.modes = []; }
    get changeTrackingMode() { this._need('changeTrackingMode'); return this._mode; }
    set changeTrackingMode(v) { this._mode = v; this.modes.push(v); }
    get body() { return new WBody(ctx, body); }
    getSelection() {
      const s = model.selection;
      return s ? new WSelection(ctx, body, body[s[0]], s[1], body[s[2]], s[3]) : new WSelection(ctx, body, body[0], 0, body[0], 0);
    }
    get sections() {
      const sec = { getHeader: k => (k === 'Primary' ? new WBody(ctx, header) : empty()), getFooter: () => empty() };
      return new Collection(ctx, [sec]);
    }
  })();
  const Word = { run: fn => fn(Object.assign(ctx, { document: doc })) };
  return { Word, ctx, doc, body, header, text: ps => ps.map(p => p.text), fmt: ps => ps.map(p => p.cs.map(x => x.f).join('')) };
}

// ------------------------------------------------------------------ Excel
class XRange extends Obj {
  constructor(ctx, sheet, r0, c0, r1, c1) { super(ctx); Object.assign(this, { sheet, r0, c0, r1, c1, isNullObject: false }); }
  get formulas() { this._need('formulas'); return this._grid(c => c.formula ?? c.value ?? ''); }
  get values() { this._need('values'); return this._grid(c => c.value ?? ''); }
  _grid(f) {
    const out = [];
    for (let r = this.r0; r <= this.r1; r++) { const row = []; for (let c = this.c0; c <= this.c1; c++) row.push(f(this.sheet.cell(r, c))); out.push(row); }
    return out;
  }
  getCell(r, c) { return new XRange(this._ctx, this.sheet, this.r0 + r, this.c0 + c, this.r0 + r, this.c0 + c); }
  set values(v) {
    // what Excel does with a typed value: a leading apostrophe keeps text, numbers and dates are parsed
    let x = v[0][0];
    const cell = this.sheet.cell(this.r0, this.c0);
    delete cell.formula;
    if (typeof x === 'string' && x.startsWith("'")) cell.value = x.slice(1), cell.prefix = true;
    else if (typeof x === 'string' && x.trim() !== '' && !isNaN(Number(x))) cell.value = Number(x);
    else cell.value = x;
    this.sheet.writes++;
  }
  getIntersectionOrNullObject(o) {
    const r0 = Math.max(this.r0, o.r0), c0 = Math.max(this.c0, o.c0), r1 = Math.min(this.r1, o.r1), c1 = Math.min(this.c1, o.c1);
    return r0 <= r1 && c0 <= c1 ? new XRange(this._ctx, this.sheet, r0, c0, r1, c1) : Object.assign(new XRange(this._ctx, this.sheet, 0, 0, -1, -1), { isNullObject: true });
  }
  get worksheet() { return this.sheet.api; }
}

class XSheet {
  constructor(ctx, cells) { this.ctx = ctx; this.cells = cells; this.writes = 0; this.api = { getUsedRangeOrNullObject: () => this.used(), getUsedRange: () => this.used() }; }
  cell(r, c) { const k = r + ',' + c; return this.cells[k] || (this.cells[k] = {}); }
  used() {
    const keys = Object.keys(this.cells).filter(k => this.cells[k].value !== undefined && this.cells[k].value !== '');
    if (!keys.length) return Object.assign(new XRange(this.ctx, this, 0, 0, -1, -1), { isNullObject: true });
    const rc = keys.map(k => k.split(',').map(Number));
    return new XRange(this.ctx, this, Math.min(...rc.map(x => x[0])), Math.min(...rc.map(x => x[1])), Math.max(...rc.map(x => x[0])), Math.max(...rc.map(x => x[1])));
  }
}

export function fakeExcel(sheets, selection) {
  // sheets: [{ 'r,c': {value, formula} }], selection: [sheet, r0, c0, r1, c1]
  const ctx = new Ctx();
  const ws = sheets.map(cells => new XSheet(ctx, cells));
  const workbook = {
    worksheets: new Collection(ctx, ws.map(s => s.api)),
    getSelectedRange: () => { const [s, r0, c0, r1, c1] = selection; return new XRange(ctx, ws[s], r0, c0, r1, c1); },
  };
  return { Excel: { run: fn => fn(Object.assign(ctx, { workbook })) }, ctx, sheets: ws };
}

// ------------------------------------------------------------------ PowerPoint
class PText extends Obj {
  constructor(ctx, shape, start, len) { super(ctx); Object.assign(this, { shape, start, len }); }
  get text() { this._need('text'); return str(this.shape.cs.slice(this.start, this.len == null ? undefined : this.start + this.len)); }
  set text(t) {
    const end = this.len == null ? this.shape.cs.length : this.start + this.len;
    const f = (this.shape.cs[this.start] || {}).f;
    this.shape.cs.splice(this.start, end - this.start, ...chars(t, f));
  }
  getSubstring(start, len) { return new PText(this._ctx, this.shape, start, len); }
}

export function fakePowerPoint(slides, opts = {}) {
  // slides: [[{type, runs: [[text, fmt]...]}]]
  const ctx = new Ctx();
  const model = slides.map(sh => sh.map(s => ({ type: s.type, cs: (s.runs || []).flatMap(([t, f]) => chars(t, f)), noText: s.noText })));
  const shapeObj = m => Object.assign(new Obj(ctx), {
    get type() { return m.type; },
    get textFrame() {
      return { textRange: (() => { const t = new PText(ctx, m, 0, null); if (m.noText) t._poison = true; return t; })() };
    },
  });
  const slideObjs = model.map(sh => ({ shapes: new Collection(ctx, sh.map(shapeObj)) }));
  // a text frame that the host refuses (a picture placeholder): any batch that loads it fails
  ctx.failNext = null;
  const origSync = ctx.sync.bind(ctx);
  ctx.sync = () => { if (ctx.pending.some(o => o._poison)) { ctx.pending = ctx.pending.filter(o => !o._poison); ctx.syncs++; ctx.pending = []; return Promise.reject(new Error('InvalidArgument')); } return origSync(); };
  const presentation = { slides: new Collection(ctx, slideObjs), getSelectedShapes: () => new Collection(ctx, (opts.selected || []).map(([s, i]) => slideObjs[s].shapes._items[i])) };
  return { PowerPoint: { run: fn => fn(Object.assign(ctx, { presentation })) }, ctx, model, text: () => model.map(sh => sh.map(m => str(m.cs))), fmt: () => model.map(sh => sh.map(m => m.cs.map(x => x.f).join(''))) };
}

// ------------------------------------------------------------------ Office
export function fakeOffice(host, sets, selected) {
  const doc = {
    text: selected,
    getSelectedDataAsync(type, cb) { cb({ status: 'ok', value: this.text }); },
    setSelectedDataAsync(text, opts, cb) { this.text = text; cb({ status: 'ok' }); },
  };
  return {
    context: {
      host,
      document: doc,
      requirements: { isSetSupported: (name, v) => (sets[name] != null && Number(sets[name]) >= Number(v)) },
    },
    HostType: { Word: 'Word', Excel: 'Excel', PowerPoint: 'PowerPoint' },
    CoercionType: { Text: 'text' },
    AsyncResultStatus: { Succeeded: 'ok' },
  };
}
