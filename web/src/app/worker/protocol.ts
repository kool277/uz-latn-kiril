import type { EngineKind } from '../engine/engines';
import type { Encoding } from '../engine/encoding';
import type { ExportFormat } from '../engine/export';
import type { ConvertOptions, DocumentResult, Script, Source } from '../engine/types';

/** Messages between the page and a conversion worker. Byte buffers are transferred, never copied. */
export type WorkerRequest =
  | { type: 'init'; id: number; module: WebAssembly.Module | null; wasmUrl: string }
  | { type: 'text'; id: number; text: string; from: Source; to: Script; options: ConvertOptions }
  | { type: 'detect'; id: number; text: string }
  | { type: 'document'; id: number; name: string; bytes: Uint8Array; from: Source; to: Script; options: ConvertOptions }
  | { type: 'chunk'; id: number; bytes: Uint8Array; encoding: Encoding; outEncoding: Encoding; outBom: boolean; from: Script; to: Script; options: ConvertOptions }
  | { type: 'export'; id: number; text: string; format: ExportFormat; script: Script }
  | { type: 'zip'; id: number; files: Array<{ name: string; data: Uint8Array }> };

export type WorkerResponse =
  | { type: 'ready'; id: number; kind: EngineKind }
  | { type: 'text'; id: number; text: string; from: Script }
  | { type: 'detect'; id: number; script: Script }
  | { type: 'document'; id: number; result: DocumentResult }
  | { type: 'bytes'; id: number; bytes: Uint8Array }
  | { type: 'error'; id: number; code: string; detail: string };
