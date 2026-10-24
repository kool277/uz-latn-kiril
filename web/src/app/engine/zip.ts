import { deflateSync, inflateSync } from 'fflate';
import { ConversionError } from './types';

/**
 * ZIP container reader/writer for OOXML, ODF and EPUB packages. Entries keep their order, names, extra
 * fields, timestamps and compression method; unchanged entries are copied byte for byte (pictures, fonts
 * and media are never recompressed) and only replaced entries are compressed again.
 */

export interface ZipLimits {
  maxEntries: number;
  maxTotalSize: number; // sum of uncompressed sizes
  maxRatio: number; // uncompressed / compressed, checked for large entries
}

export const DEFAULT_ZIP_LIMITS: ZipLimits = { maxEntries: 20000, maxTotalSize: 2 * 1024 ** 3, maxRatio: 1000 };

export interface ZipEntry {
  name: string;
  nameBytes: Uint8Array;
  versionMadeBy: number;
  versionNeeded: number;
  flags: number;
  method: number;
  time: number;
  date: number;
  crc: number;
  compressedSize: number;
  size: number;
  internalAttr: number;
  externalAttr: number;
  cdExtra: Uint8Array;
  localExtra: Uint8Array;
  comment: Uint8Array;
  dataOffset: number;
  replacement?: Uint8Array;
}

const SIG_LOCAL = 0x04034b50, SIG_CD = 0x02014b50, SIG_EOCD = 0x06054b50, SIG_Z64_LOC = 0x07064b50, SIG_Z64_EOCD = 0x06064b50;

function corrupt(detail: string): never {
  throw new ConversionError('err.corrupt', detail);
}

const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

export function crc32(data: Uint8Array): number {
  let c = -1;
  for (let i = 0; i < data.length; i++) c = CRC_TABLE[(c ^ data[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

/** Drops the ZIP64 extra field: the writer emits plain 32-bit headers. */
function stripZip64(extra: Uint8Array): Uint8Array {
  const dv = new DataView(extra.buffer, extra.byteOffset, extra.byteLength);
  const keep: Uint8Array[] = [];
  let p = 0;
  while (p + 4 <= extra.length) {
    const id = dv.getUint16(p, true), len = dv.getUint16(p + 2, true);
    if (p + 4 + len > extra.length) break;
    if (id !== 0x0001) keep.push(extra.subarray(p, p + 4 + len));
    p += 4 + len;
  }
  if (keep.length === 1 && keep[0].length === extra.length) return extra;
  const out = new Uint8Array(keep.reduce((n, k) => n + k.length, 0));
  let o = 0;
  for (const k of keep) { out.set(k, o); o += k.length; }
  return out;
}

export class ZipArchive {
  readonly entries: ZipEntry[] = [];
  comment: Uint8Array = new Uint8Array(0);

  private constructor(private readonly bytes: Uint8Array, private readonly limits: ZipLimits) {}

  static isZip(b: Uint8Array): boolean {
    return b.length >= 4 && b[0] === 0x50 && b[1] === 0x4b && b[2] === 0x03 && b[3] === 0x04;
  }

  static read(bytes: Uint8Array, limits: ZipLimits = DEFAULT_ZIP_LIMITS): ZipArchive {
    const z = new ZipArchive(bytes, limits);
    z.parse();
    return z;
  }

  private parse(): void {
    const b = this.bytes;
    const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
    let eocd = -1;
    for (let p = b.length - 22; p >= Math.max(0, b.length - 22 - 0xffff); p--) {
      if (dv.getUint32(p, true) === SIG_EOCD && p + 22 + dv.getUint16(p + 20, true) <= b.length) { eocd = p; break; }
    }
    if (eocd < 0) corrupt('no end of central directory');
    if (dv.getUint16(eocd + 4, true) !== 0 || dv.getUint16(eocd + 6, true) !== 0) throw new ConversionError('err.multidisk');
    let count = dv.getUint16(eocd + 10, true);
    let cdSize = dv.getUint32(eocd + 12, true);
    let cdOffset = dv.getUint32(eocd + 16, true);
    this.comment = b.slice(eocd + 22, eocd + 22 + dv.getUint16(eocd + 20, true));
    if ((count === 0xffff || cdSize === 0xffffffff || cdOffset === 0xffffffff) && eocd >= 20 &&
      dv.getUint32(eocd - 20, true) === SIG_Z64_LOC) {
      const z64 = Number(dv.getBigUint64(eocd - 12, true));
      if (z64 + 56 > b.length || dv.getUint32(z64, true) !== SIG_Z64_EOCD) corrupt('bad zip64 record');
      count = Number(dv.getBigUint64(z64 + 32, true));
      cdSize = Number(dv.getBigUint64(z64 + 40, true));
      cdOffset = Number(dv.getBigUint64(z64 + 48, true));
    }
    if (count > this.limits.maxEntries) throw new ConversionError('err.tooManyEntries');
    if (cdOffset + cdSize > b.length) corrupt('central directory out of range');
    let p = cdOffset, total = 0;
    const utf8 = new TextDecoder('utf-8');
    for (let i = 0; i < count; i++) {
      if (p + 46 > b.length || dv.getUint32(p, true) !== SIG_CD) corrupt('bad central directory entry');
      const nameLen = dv.getUint16(p + 28, true), extraLen = dv.getUint16(p + 30, true), commentLen = dv.getUint16(p + 32, true);
      const nameBytes = b.slice(p + 46, p + 46 + nameLen);
      const cdExtra = b.slice(p + 46 + nameLen, p + 46 + nameLen + extraLen);
      const e: ZipEntry = {
        name: utf8.decode(nameBytes),
        nameBytes,
        versionMadeBy: dv.getUint16(p + 4, true),
        versionNeeded: dv.getUint16(p + 6, true),
        flags: dv.getUint16(p + 8, true),
        method: dv.getUint16(p + 10, true),
        time: dv.getUint16(p + 12, true),
        date: dv.getUint16(p + 14, true),
        crc: dv.getUint32(p + 16, true),
        compressedSize: dv.getUint32(p + 20, true),
        size: dv.getUint32(p + 24, true),
        internalAttr: dv.getUint16(p + 36, true),
        externalAttr: dv.getUint32(p + 38, true),
        cdExtra,
        localExtra: new Uint8Array(0),
        comment: b.slice(p + 46 + nameLen + extraLen, p + 46 + nameLen + extraLen + commentLen),
        dataOffset: 0
      };
      let localOffset = dv.getUint32(p + 42, true);
      if (e.size === 0xffffffff || e.compressedSize === 0xffffffff || localOffset === 0xffffffff) {
        // ZIP64 extended information: the 64-bit values follow in this order, each only if its field is saturated
        const xv = new DataView(cdExtra.buffer, cdExtra.byteOffset, cdExtra.byteLength);
        for (let q = 0; q + 4 <= cdExtra.length;) {
          const id = xv.getUint16(q, true), len = xv.getUint16(q + 2, true);
          if (id === 0x0001) {
            let r = q + 4;
            if (e.size === 0xffffffff) { e.size = Number(xv.getBigUint64(r, true)); r += 8; }
            if (e.compressedSize === 0xffffffff) { e.compressedSize = Number(xv.getBigUint64(r, true)); r += 8; }
            if (localOffset === 0xffffffff) { localOffset = Number(xv.getBigUint64(r, true)); }
            break;
          }
          q += 4 + len;
        }
      }
      if (e.flags & 0x0001) throw new ConversionError('err.encrypted');
      if (localOffset + 30 > b.length || dv.getUint32(localOffset, true) !== SIG_LOCAL) corrupt('bad local header for ' + e.name);
      const lName = dv.getUint16(localOffset + 26, true), lExtra = dv.getUint16(localOffset + 28, true);
      e.localExtra = b.slice(localOffset + 30 + lName, localOffset + 30 + lName + lExtra);
      e.dataOffset = localOffset + 30 + lName + lExtra;
      if (e.dataOffset + e.compressedSize > b.length) corrupt('entry data out of range: ' + e.name);
      total += e.size;
      if (total > this.limits.maxTotalSize) throw new ConversionError('err.tooLarge');
      if (e.size > 1 << 24 && e.size / Math.max(1, e.compressedSize) > this.limits.maxRatio) throw new ConversionError('err.zipBomb');
      this.entries.push(e);
      p += 46 + nameLen + extraLen + commentLen;
    }
  }

  get(name: string): ZipEntry | undefined {
    return this.entries.find(e => e.name === name);
  }

  /** Uncompressed content, checked against the stored size and CRC-32. */
  data(e: ZipEntry): Uint8Array {
    if (e.replacement) return e.replacement;
    const raw = this.bytes.subarray(e.dataOffset, e.dataOffset + e.compressedSize);
    let out: Uint8Array;
    if (e.method === 0) out = raw;
    else if (e.method === 8) {
      out = new Uint8Array(e.size);
      try { out = inflateSync(raw, { out }); } catch { corrupt('cannot inflate ' + e.name); }
    } else throw new ConversionError('err.zipMethod', String(e.method));
    if (out.length !== e.size || crc32(out) !== e.crc) corrupt('checksum mismatch in ' + e.name);
    return out;
  }

  text(e: ZipEntry): string {
    return new TextDecoder('utf-8').decode(this.data(e));
  }

  replace(e: ZipEntry, data: Uint8Array): void {
    e.replacement = data;
  }

  get changed(): boolean {
    return this.entries.some(e => e.replacement);
  }

  write(): Uint8Array {
    type Out = { e: ZipEntry; data: Uint8Array; crc: number; size: number; flags: number; localExtra: Uint8Array; cdExtra: Uint8Array };
    const outs: Out[] = [];
    let total = 0;
    for (const e of this.entries) {
      let data: Uint8Array, crc = e.crc, size = e.size;
      if (e.replacement) {
        crc = crc32(e.replacement);
        size = e.replacement.length;
        data = e.method === 0 ? e.replacement : deflateSync(e.replacement, { level: 6 });
      } else data = this.bytes.subarray(e.dataOffset, e.dataOffset + e.compressedSize);
      if (size > 0xfffffffe || data.length > 0xfffffffe) throw new ConversionError('err.tooLarge');
      const o: Out = { e, data, crc, size, flags: e.flags & ~0x0008, localExtra: stripZip64(e.localExtra), cdExtra: stripZip64(e.cdExtra) };
      outs.push(o);
      total += 30 + e.nameBytes.length + o.localExtra.length + data.length + 46 + e.nameBytes.length + o.cdExtra.length + e.comment.length;
    }
    if (outs.length > 0xfffe) throw new ConversionError('err.tooManyEntries');
    total += 22 + this.comment.length;
    if (total > 0xfffffffe) throw new ConversionError('err.tooLarge');
    const buf = new Uint8Array(total);
    const dv = new DataView(buf.buffer);
    let p = 0;
    const offsets: number[] = [];
    for (const o of outs) {
      const e = o.e;
      offsets.push(p);
      dv.setUint32(p, SIG_LOCAL, true);
      dv.setUint16(p + 4, Math.min(e.versionNeeded, 45), true);
      dv.setUint16(p + 6, o.flags, true);
      dv.setUint16(p + 8, e.method, true);
      dv.setUint16(p + 10, e.time, true);
      dv.setUint16(p + 12, e.date, true);
      dv.setUint32(p + 14, o.crc, true);
      dv.setUint32(p + 18, o.data.length, true);
      dv.setUint32(p + 22, o.size, true);
      dv.setUint16(p + 26, e.nameBytes.length, true);
      dv.setUint16(p + 28, o.localExtra.length, true);
      buf.set(e.nameBytes, p + 30);
      buf.set(o.localExtra, p + 30 + e.nameBytes.length);
      p += 30 + e.nameBytes.length + o.localExtra.length;
      buf.set(o.data, p);
      p += o.data.length;
    }
    const cdStart = p;
    outs.forEach((o, i) => {
      const e = o.e;
      dv.setUint32(p, SIG_CD, true);
      dv.setUint16(p + 4, e.versionMadeBy, true);
      dv.setUint16(p + 6, Math.min(e.versionNeeded, 45), true);
      dv.setUint16(p + 8, o.flags, true);
      dv.setUint16(p + 10, e.method, true);
      dv.setUint16(p + 12, e.time, true);
      dv.setUint16(p + 14, e.date, true);
      dv.setUint32(p + 16, o.crc, true);
      dv.setUint32(p + 20, o.data.length, true);
      dv.setUint32(p + 24, o.size, true);
      dv.setUint16(p + 28, e.nameBytes.length, true);
      dv.setUint16(p + 30, o.cdExtra.length, true);
      dv.setUint16(p + 32, e.comment.length, true);
      dv.setUint16(p + 34, 0, true);
      dv.setUint16(p + 36, e.internalAttr, true);
      dv.setUint32(p + 38, e.externalAttr, true);
      dv.setUint32(p + 42, offsets[i], true);
      buf.set(e.nameBytes, p + 46);
      buf.set(o.cdExtra, p + 46 + e.nameBytes.length);
      buf.set(e.comment, p + 46 + e.nameBytes.length + o.cdExtra.length);
      p += 46 + e.nameBytes.length + o.cdExtra.length + e.comment.length;
    });
    dv.setUint32(p, SIG_EOCD, true);
    dv.setUint16(p + 8, outs.length, true);
    dv.setUint16(p + 10, outs.length, true);
    dv.setUint32(p + 12, p - cdStart, true);
    dv.setUint32(p + 16, cdStart, true);
    dv.setUint16(p + 20, this.comment.length, true);
    buf.set(this.comment, p + 22);
    return buf;
  }
}

/** Builds a new archive (used for exports and "download all"). Entries are written in the given order. */
export function buildZip(files: Array<{ name: string; data: Uint8Array; store?: boolean }>, date = new Date()): Uint8Array {
  const time = (date.getHours() << 11) | (date.getMinutes() << 5) | (date.getSeconds() >> 1);
  const ddate = ((date.getFullYear() - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate();
  const enc = new TextEncoder();
  const parts = files.map(f => {
    const nameBytes = enc.encode(f.name);
    const data = f.store ? f.data : deflateSync(f.data, { level: 6 });
    return { nameBytes, raw: f.data, data, method: f.store ? 0 : 8, crc: crc32(f.data) };
  });
  let total = 22;
  for (const p of parts) total += 30 + 46 + 2 * p.nameBytes.length + p.data.length;
  if (total > 0xfffffffe || parts.length > 0xfffe) throw new ConversionError('err.tooLarge');
  const buf = new Uint8Array(total);
  const dv = new DataView(buf.buffer);
  let p = 0;
  const offsets: number[] = [];
  for (const f of parts) {
    offsets.push(p);
    dv.setUint32(p, SIG_LOCAL, true);
    dv.setUint16(p + 4, 20, true);
    dv.setUint16(p + 6, 0x0800, true); // UTF-8 names
    dv.setUint16(p + 8, f.method, true);
    dv.setUint16(p + 10, time, true);
    dv.setUint16(p + 12, ddate, true);
    dv.setUint32(p + 14, f.crc, true);
    dv.setUint32(p + 18, f.data.length, true);
    dv.setUint32(p + 22, f.raw.length, true);
    dv.setUint16(p + 26, f.nameBytes.length, true);
    dv.setUint16(p + 28, 0, true);
    buf.set(f.nameBytes, p + 30);
    p += 30 + f.nameBytes.length;
    buf.set(f.data, p);
    p += f.data.length;
  }
  const cd = p;
  parts.forEach((f, i) => {
    dv.setUint32(p, SIG_CD, true);
    dv.setUint16(p + 4, 0x031e, true); // made by UNIX, spec 3.0
    dv.setUint16(p + 6, 20, true);
    dv.setUint16(p + 8, 0x0800, true);
    dv.setUint16(p + 10, f.method, true);
    dv.setUint16(p + 12, time, true);
    dv.setUint16(p + 14, ddate, true);
    dv.setUint32(p + 16, f.crc, true);
    dv.setUint32(p + 20, f.data.length, true);
    dv.setUint32(p + 24, f.raw.length, true);
    dv.setUint16(p + 28, f.nameBytes.length, true);
    dv.setUint32(p + 38, 0o100644 << 16, true);
    dv.setUint32(p + 42, offsets[i], true);
    buf.set(f.nameBytes, p + 46);
    p += 46 + f.nameBytes.length;
  });
  dv.setUint32(p, SIG_EOCD, true);
  dv.setUint16(p + 8, parts.length, true);
  dv.setUint16(p + 10, parts.length, true);
  dv.setUint32(p + 12, p - cd, true);
  dv.setUint32(p + 16, cd, true);
  return buf;
}
