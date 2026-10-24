/// <reference lib="webworker" />
import { convertDocument } from '../engine/document';
import { encodeText } from '../engine/encoding';
import { createEngine, EngineKind } from '../engine/engines';
import { exportText } from '../engine/export';
import { ConversionError, Converter } from '../engine/types';
import { buildZip } from '../engine/zip';
import type { WorkerRequest, WorkerResponse } from './protocol';

// One conversion engine per worker; the page runs one worker per CPU core.
let engine: Promise<{ engine: Converter; kind: EngineKind }> | null = null;

function reply(msg: WorkerResponse, transfer: Transferable[] = []): void {
  postMessage(msg, transfer);
}

addEventListener('message', async (ev: MessageEvent<WorkerRequest>) => {
  const msg = ev.data;
  try {
    if (msg.type === 'init') {
      engine = createEngine(msg.module ?? (await fetch(new URL(msg.wasmUrl, location.href)).catch(() => null)));
      reply({ type: 'ready', id: msg.id, kind: (await engine).kind });
      return;
    }
    if (msg.type === 'export') {
      const bytes = exportText(msg.text, msg.format, msg.script);
      reply({ type: 'bytes', id: msg.id, bytes }, [bytes.buffer]);
      return;
    }
    if (msg.type === 'zip') {
      const bytes = buildZip(msg.files);
      reply({ type: 'bytes', id: msg.id, bytes }, [bytes.buffer]);
      return;
    }
    if (!engine) throw new ConversionError('err.internal', 'worker not initialised');
    const { engine: U } = await engine;
    switch (msg.type) {
      case 'text': {
        const r = U.convertSegments([msg.text], msg.from, msg.to, msg.options);
        reply({ type: 'text', id: msg.id, text: r.pieces[0], from: r.from });
        break;
      }
      case 'detect':
        reply({ type: 'detect', id: msg.id, script: U.detect(msg.text) });
        break;
      case 'document': {
        const result = convertDocument(U, { name: msg.name, bytes: msg.bytes, from: msg.from, to: msg.to, options: msg.options });
        reply({ type: 'document', id: msg.id, result }, [result.bytes.buffer]);
        break;
      }
      case 'chunk': {
        const text = new TextDecoder(msg.encoding, { ignoreBOM: true }).decode(msg.bytes);
        const out = msg.from === msg.to ? text : U.convert(text, msg.from, msg.to, msg.options);
        const bytes = encodeText(out, msg.outEncoding, msg.outBom);
        reply({ type: 'bytes', id: msg.id, bytes }, [bytes.buffer]);
        break;
      }
    }
  } catch (e) {
    const code = e instanceof ConversionError ? e.code : 'err.internal';
    reply({ type: 'error', id: msg.id, code, detail: e instanceof Error ? e.message : String(e) });
  }
});
