import { Injectable, signal } from '@angular/core';
import { WASM_URL } from '../../generated/engine-assets';
import type { EngineKind } from '../engine/engines';
import { outputName } from '../engine/names';
import type { ExportFormat } from '../engine/export';
import { PARALLEL_TEXT_MIN, planTextFile } from '../engine/textfile';
import { ConversionError, ConvertOptions, DocumentResult, Script, Source } from '../engine/types';
import type { WorkerRequest, WorkerResponse } from '../worker/protocol';

/** a request without its id (Omit distributed over the union) */
type Request = WorkerRequest extends infer R ? (R extends WorkerRequest ? Omit<R, 'id'> : never) : never;

interface Pending {
  resolve(r: WorkerResponse): void;
  reject(e: unknown): void;
}

/** A worker with its own engine instance. */
class Slot {
  readonly worker: Worker;
  readonly ready: Promise<EngineKind>;
  busy = false;
  /** the worker crashed (out of memory, …); the slot must be replaced */
  dead = false;
  private readonly pending = new Map<number, Pending>();
  private seq = 0;

  constructor(module: Promise<WebAssembly.Module | null>) {
    this.worker = new Worker(new URL('../worker/convert.worker', import.meta.url), { type: 'module', name: 'uztranslit' });
    this.worker.onmessage = (ev: MessageEvent<WorkerResponse>) => {
      const p = this.pending.get(ev.data.id);
      if (!p) return;
      this.pending.delete(ev.data.id);
      if (ev.data.type === 'error') p.reject(new ConversionError(ev.data.code, ev.data.detail));
      else p.resolve(ev.data);
    };
    this.worker.onerror = ev => {
      ev.preventDefault();
      this.dead = true;
      this.fail(new ConversionError('err.internal', ev.message || 'worker stopped'));
    };
    this.ready = module.then(m => this.call({ type: 'init', module: m, wasmUrl: WASM_URL })).then(r => (r.type === 'ready' ? r.kind : 'js'));
  }

  call(req: Request, transfer: Transferable[] = []): Promise<WorkerResponse> {
    const id = ++this.seq;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.worker.postMessage({ ...req, id } as WorkerRequest, transfer);
    });
  }

  fail(e: unknown): void {
    for (const p of this.pending.values()) p.reject(e);
    this.pending.clear();
  }

  terminate(): void {
    this.worker.terminate();
    this.fail(new ConversionError('err.cancelled'));
  }
}

interface Task<T> {
  run(slot: Slot): Promise<T>;
  resolve(v: T): void;
  reject(e: unknown): void;
  slot?: Slot;
  cancelled?: boolean;
}

export interface Cancellable<T> {
  promise: Promise<T>;
  cancel(): void;
}

export interface FileOutcome {
  name: string;
  blob: Blob;
  from: Script;
  to: Script;
  format: string;
  encoding?: string;
  stats?: DocumentResult['stats'];
  warnings: string[];
}

export const MAX_FILE_BYTES = 512 * 1024 * 1024;

/** The pieces of one file conversion, so that cancelling stops all of them. */
interface Run {
  parts: Array<Cancellable<unknown>>;
  cancelled: boolean;
}

/**
 * Runs conversions on Web Workers, one per CPU core (up to 8), each with its own instance of the
 * WebAssembly engine; the module is compiled once and shared. One extra worker serves the text editor
 * so typing stays responsive while files convert.
 */
@Injectable({ providedIn: 'root' })
export class EngineService {
  readonly kind = signal<EngineKind | null>(null);
  readonly threads = Math.max(1, Math.min((globalThis.navigator?.hardwareConcurrency ?? 4) - 1, 8));
  readonly running = signal(0);

  private readonly module: Promise<WebAssembly.Module | null>;
  private editor: Slot | null = null;
  private readonly pool: Slot[] = [];
  private readonly queue: Array<Task<unknown>> = [];

  constructor() {
    this.module = this.compile();
  }

  private async compile(): Promise<WebAssembly.Module | null> {
    if (typeof WebAssembly !== 'object') return null;
    const url = new URL(WASM_URL, document.baseURI).href;
    try {
      return await WebAssembly.compileStreaming(fetch(url));
    } catch {
      try { // a server without the application/wasm MIME type
        return await WebAssembly.compile(await (await fetch(url)).arrayBuffer());
      } catch {
        return null;
      }
    }
  }

  private async editorSlot(): Promise<Slot> {
    if (this.editor?.dead) {
      this.editor.terminate();
      this.editor = null;
    }
    if (!this.editor) {
      this.editor = new Slot(this.module);
      this.editor.ready.then(k => this.kind.set(k), () => this.kind.set(null));
    }
    const slot = this.editor;
    await slot.ready;
    return slot;
  }

  /** Starts the engine early so the first conversion is instant. */
  warmUp(): void {
    void this.editorSlot();
  }

  async convertText(text: string, from: Source, to: Script, options: ConvertOptions): Promise<{ text: string; from: Script }> {
    const r = await (await this.editorSlot()).call({ type: 'text', text, from, to, options });
    if (r.type !== 'text') throw new ConversionError('err.internal');
    return { text: r.text, from: r.from };
  }

  async detect(text: string): Promise<Script> {
    const r = await (await this.editorSlot()).call({ type: 'detect', text });
    if (r.type !== 'detect') throw new ConversionError('err.internal');
    return r.script;
  }

  async exportText(text: string, format: ExportFormat, script: Script): Promise<Uint8Array> {
    const r = await (await this.editorSlot()).call({ type: 'export', text, format, script });
    if (r.type !== 'bytes') throw new ConversionError('err.internal');
    return r.bytes;
  }

  // ---------------------------------------------------------------- the pool

  private schedule<T>(run: (slot: Slot) => Promise<T>): Cancellable<T> {
    let task!: Task<T>;
    const promise = new Promise<T>((resolve, reject) => { task = { run, resolve, reject }; });
    this.queue.push(task as Task<unknown>);
    this.pump();
    return {
      promise,
      cancel: () => {
        if (task.cancelled) return;
        task.cancelled = true;
        const i = this.queue.indexOf(task as Task<unknown>);
        if (i >= 0) this.queue.splice(i, 1);
        if (task.slot) this.replace(task.slot); // stop the work in progress
        task.reject(new ConversionError('err.cancelled'));
      }
    };
  }

  private replace(slot: Slot): void {
    const i = this.pool.indexOf(slot);
    slot.terminate();
    if (i >= 0) this.pool.splice(i, 1);
    this.pump();
  }

  private pump(): void {
    while (this.queue.length) {
      let slot = this.pool.find(s => !s.busy);
      if (!slot && this.pool.length < this.threads) {
        slot = new Slot(this.module);
        this.pool.push(slot);
        slot.ready.then(k => { if (!this.kind()) this.kind.set(k); }, () => undefined);
      }
      if (!slot) return;
      const task = this.queue.shift();
      if (!task) return;
      slot.busy = true;
      task.slot = slot;
      this.running.update(n => n + 1);
      const s = slot;
      void (async () => {
        try {
          await s.ready;
          task.resolve(await task.run(s));
        } catch (e) {
          if (!task.cancelled) task.reject(e);
        } finally {
          s.busy = false;
          this.running.update(n => n - 1);
          if (s.dead) this.replace(s);
          else this.pump();
        }
      })();
    }
  }

  /** Converts any supported file. Large plain-text files are split and converted on all workers. */
  convertFile(file: File, from: Source, to: Script, options: ConvertOptions, onProgress?: (p: number) => void): Cancellable<FileOutcome> {
    if (file.size > MAX_FILE_BYTES) return { promise: Promise.reject(new ConversionError('err.tooLarge')), cancel() {} };
    const run: Run = { parts: [], cancelled: false };
    const promise = (async (): Promise<FileOutcome> => {
      const bytes = new Uint8Array(await file.arrayBuffer());
      if (run.cancelled) throw new ConversionError('err.cancelled');
      if (bytes.length >= PARALLEL_TEXT_MIN && /\.(txt|text|log|csv|tsv)$/i.test(file.name)) {
        return this.convertLargeText(file, bytes, from, to, options, run, onProgress);
      }
      const job = this.schedule(slot => {
        onProgress?.(0);
        return slot.call({ type: 'document', name: file.name, bytes, from, to, options }, [bytes.buffer]);
      });
      run.parts.push(job);
      const r = await job.promise;
      if (r.type !== 'document') throw new ConversionError('err.internal');
      onProgress?.(1);
      const res = r.result;
      return { name: res.name, blob: new Blob([res.bytes as BlobPart], { type: res.mime }), from: res.from, to, format: res.format, encoding: res.encoding, stats: res.stats, warnings: res.warnings };
    })();
    return { promise, cancel: () => { run.cancelled = true; run.parts.forEach(p => p.cancel()); } };
  }

  private async convertLargeText(file: File, bytes: Uint8Array, from: Source, to: Script, options: ConvertOptions,
    run: Run, onProgress?: (p: number) => void): Promise<FileOutcome> {
    onProgress?.(0);
    const plan = planTextFile(bytes);
    let source: Script;
    if (from === 'auto') {
      const [s] = plan.ranges[0];
      const sample = new TextDecoder(plan.encoding, { ignoreBOM: true }).decode(bytes.subarray(s, Math.min(bytes.length, s + (1 << 20))));
      const r = await (await this.editorSlot()).call({ type: 'detect', text: sample });
      source = r.type === 'detect' ? r.script : 'lat';
    } else source = from;
    if (run.cancelled) throw new ConversionError('err.cancelled');
    if (source === to) return { name: outputName(file.name, to), blob: file, from: source, to, format: 'text', encoding: plan.encoding, warnings: ['warn.sameScript'] };
    let done = 0;
    const jobs = plan.ranges.map(([s, e], i) => {
      const chunk = bytes.slice(s, e);
      const job = this.schedule(slot => slot.call({ type: 'chunk', bytes: chunk, encoding: plan.encoding, outEncoding: plan.outEncoding, outBom: i === 0 && plan.outBom, from: source, to, options }, [chunk.buffer])
        .then(r => {
          onProgress?.(++done / plan.ranges.length);
          if (r.type !== 'bytes') throw new ConversionError('err.internal');
          return r.bytes;
        }));
      run.parts.push(job);
      return job.promise;
    });
    const out = await Promise.all(jobs);
    const mime = /\.csv$/i.test(file.name) ? 'text/csv' : /\.tsv$/i.test(file.name) ? 'text/tab-separated-values' : 'text/plain';
    return { name: outputName(file.name, to), blob: new Blob(out as BlobPart[], { type: mime }), from: source, to, format: 'text', encoding: plan.encoding, warnings: [] };
  }

  /** Packs results into one ZIP on a worker. */
  zip(files: Array<{ name: string; data: Uint8Array }>): Cancellable<Uint8Array> {
    return this.schedule(async slot => {
      const r = await slot.call({ type: 'zip', files }, files.map(f => f.data.buffer));
      if (r.type !== 'bytes') throw new ConversionError('err.internal');
      return r.bytes;
    });
  }
}
