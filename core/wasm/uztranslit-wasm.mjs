/*!
 * uztranslit-wasm v1.0.0 — JavaScript glue for the WebAssembly port of spec/SPEC.md (assembly/index.ts).
 * Same public API as core/js/uztranslit.js (convert, detect, cyrToLat …), plus convertSegments(), which
 * converts a run of text segments (rich-text runs) as one string and hands back one result per segment.
 * MIT License.
 */

export const VERSION = '1.1.0';
export const SCRIPTS = Object.freeze(['cyr', 'lat', 'new']);
export const DEFAULTS = Object.freeze({
  okina: 'ʻ',
  tutuq: 'ʼ',
  dropHardSignAfterO: true,
  tsFinal: true,
  dictionary: true,
  skipUrls: true
});

const CODE = { cyr: 0, lat: 1, new: 2, auto: 3 };
const OPT = { dropHardSignAfterO: 1, tsFinal: 2, dictionary: 4, skipUrls: 8 };
const IMPORTS = {
  env: {
    abort() { throw new Error('uztranslit-wasm: engine aborted'); }
  }
};

/** Compiles (unless given a WebAssembly.Module) and instantiates the engine. */
export async function instantiate(source) {
  let module;
  if (source instanceof WebAssembly.Module) module = source;
  else if (typeof Response !== 'undefined' && source instanceof Response) module = await WebAssembly.compileStreaming(source);
  else module = await WebAssembly.compile(source);
  return new UzTranslitWasm(await WebAssembly.instantiate(module, IMPORTS));
}

/** Wraps build/uztranslit.engine.js — the same engine translated to plain JavaScript (no WebAssembly). */
export function fromExports(exports) {
  return new UzTranslitWasm({ exports });
}

function scriptCode(s, allowAuto) {
  const c = CODE[s];
  if (c === undefined || (c === 3 && !allowAuto)) throw new Error('UzTranslit: unknown script ' + s);
  return c;
}

function markCode(s, name) {
  if (s === '') return -1;
  if (typeof s !== 'string' || s.length !== 1) throw new TypeError('UzTranslit: ' + name + ' must be one character');
  return s.charCodeAt(0);
}

function wellFormed(s) {
  return typeof s.isWellFormed === 'function' ? s.isWellFormed() : !/[\uD800-\uDFFF]/.test(s);
}

export class UzTranslitWasm {
  #x;
  #decoder = new TextDecoder('utf-16le', { ignoreBOM: true });

  constructor(instance) {
    this.#x = instance.exports;
  }

  #options(o) {
    const r = { ...DEFAULTS };
    if (o) for (const k in DEFAULTS) if (o[k] !== undefined) r[k] = o[k];
    let flags = 0;
    for (const k in OPT) if (r[k]) flags |= OPT[k];
    return { flags, okina: markCode(r.okina, 'okina'), tutuq: markCode(r.tutuq, 'tutuq') };
  }

  // copies the pieces into wasm memory; returns false if a lone surrogate may be present
  #write(pieces, total) {
    const view = this.#view(Uint16Array, this.#x.inputBuffer(total), total);
    let k = 0, ok = true;
    for (const s of pieces) {
      if (ok && !wellFormed(s)) ok = false;
      for (let i = 0; i < s.length; i++) view[k++] = s.charCodeAt(i);
    }
    return ok;
  }

  // Every view is made *after* the call that may grow wasm memory: growing detaches the old buffer.
  #view(Type, ptr, len) {
    return new Type(this.#x.memory.buffer, ptr, len);
  }

  #read(len, safe) {
    const view = this.#view(Uint16Array, this.#x.outputPtr(), len);
    if (safe) return this.#decoder.decode(view);
    // TextDecoder would turn lone surrogates into U+FFFD; user text must survive unchanged
    let s = '';
    for (let i = 0; i < len; i += 0x8000) s += String.fromCharCode.apply(null, view.subarray(i, Math.min(len, i + 0x8000)));
    return s;
  }

  #run(pieces, from, to, options) {
    const f = scriptCode(from, true), t = scriptCode(to, false);
    const o = this.#options(options);
    let total = 0;
    for (const s of pieces) total += s.length;
    const safe = this.#write(pieces, total);
    const k = pieces.length - 1;
    if (k > 0) {
      const b = this.#view(Int32Array, this.#x.boundaryBuffer(k), k);
      let pos = 0;
      for (let i = 0; i < k; i++) b[i] = pos += pieces[i].length;
    }
    const len = this.#x.convert(total, f, t, o.flags, o.okina, o.tutuq, Math.max(k, 0));
    const text = this.#read(len, safe);
    const resolved = SCRIPTS[this.#x.resolvedSource()];
    let splits = null;
    if (k > 0) splits = Int32Array.from(this.#view(Int32Array, this.#x.boundaryBuffer(k), k));
    return { text, splits, from: resolved };
  }

  /** convert(text, from, to, options) — from ∈ cyr|lat|new|auto, to ∈ cyr|lat|new (SPEC §2). */
  convert(text, from, to, options) {
    text = String(text == null ? '' : text);
    return this.#run([text], from, to, options).text;
  }

  /**
   * Converts pieces.join('') and splits the result back into one string per piece, so formatting
   * attached to each piece (a Word run, an HTML element …) survives. Returns { pieces, from }.
   */
  convertSegments(pieces, from, to, options) {
    if (pieces.length === 0) return { pieces: [], from: from === 'auto' ? 'lat' : from };
    const r = this.#run(pieces, from, to, options);
    const out = new Array(pieces.length);
    let prev = 0;
    for (let i = 0; i < pieces.length - 1; i++) {
      out[i] = r.text.slice(prev, r.splits[i]);
      prev = r.splits[i];
    }
    out[pieces.length - 1] = r.text.slice(prev);
    return { pieces: out, from: r.from };
  }

  detect(text) {
    text = String(text == null ? '' : text);
    this.#write([text], text.length);
    return SCRIPTS[this.#x.detectInput(text.length)];
  }

  cyrToLat(t, o) { return this.convert(t, 'cyr', 'lat', o); }
  cyrToNew(t, o) { return this.convert(t, 'cyr', 'new', o); }
  latToCyr(t, o) { return this.convert(t, 'lat', 'cyr', o); }
  newToCyr(t, o) { return this.convert(t, 'new', 'cyr', o); }
  latToNew(t, o) { return this.convert(t, 'lat', 'new', o); }
  newToLat(t, o) { return this.convert(t, 'new', 'lat', o); }
}
