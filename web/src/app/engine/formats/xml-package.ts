import { Paragraph } from '../text-model';
import { Script } from '../types';
import { collectXml, writeXml, XmlCollected, XmlProfile } from '../xml';
import { decodeXmlBytes, encodeXmlText, XmlText } from '../xmldoc';
import { ZipArchive, ZipEntry } from '../zip';
import { Prepared } from './prepared';

/** One XML part of a package (or a standalone XML file) prepared for conversion. */
export class XmlPart {
  readonly collected: XmlCollected;

  constructor(readonly source: XmlText, profile: XmlProfile) {
    this.collected = collectXml(source.text, profile);
  }

  static fromBytes(bytes: Uint8Array, profile: XmlProfile): XmlPart {
    return new XmlPart(decodeXmlBytes(bytes), profile);
  }

  get paras(): Paragraph[] {
    return this.collected.paras;
  }

  /** Converted bytes, or null when the part is unchanged. */
  finish(to: Script): Uint8Array | null {
    const r = writeXml(this.collected, to);
    return r.changed ? encodeXmlText({ ...this.source, text: r.xml }) : null;
  }
}

/** A ZIP package whose selected XML parts (and embedded packages) are converted. */
export class PackageJob {
  readonly parts: Array<{ entry: ZipEntry; part: XmlPart }> = [];
  readonly nested: Array<{ entry: ZipEntry; prepared: Prepared }> = [];

  constructor(readonly zip: ZipArchive) {}

  addPart(entry: ZipEntry, profile: XmlProfile): void {
    this.parts.push({ entry, part: XmlPart.fromBytes(this.zip.data(entry), profile) });
  }

  addNested(entry: ZipEntry, prepared: Prepared): void {
    this.nested.push({ entry, prepared });
  }

  get paras(): Paragraph[] {
    const all: Paragraph[] = [];
    for (const p of this.parts) for (const q of p.part.paras) all.push(q);
    for (const n of this.nested) for (const q of n.prepared.paras) all.push(q);
    return all;
  }

  get count(): number {
    return this.parts.length + this.nested.reduce((s, n) => s + n.prepared.parts, 0);
  }

  finish(to: Script): Uint8Array | null {
    for (const p of this.parts) {
      const out = p.part.finish(to);
      if (out) this.zip.replace(p.entry, out);
    }
    for (const n of this.nested) {
      const out = n.prepared.finish(to);
      if (out) this.zip.replace(n.entry, out);
    }
    return this.zip.changed ? this.zip.write() : null;
  }
}
