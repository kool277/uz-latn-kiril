import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fromExports, instantiate, UzTranslitWasm } from '../../src/generated/uztranslit-wasm.js';
import * as engineJs from '../../src/generated/uztranslit-engine.js';
import { WASM_URL } from '../../src/generated/engine-assets';

export const WEB = join(__dirname, '..', '..');
export const DOCS = join(WEB, 'test', 'fixtures', 'docs');

export async function wasmEngine(): Promise<UzTranslitWasm> {
  return instantiate(readFileSync(join(WEB, 'public', WASM_URL)));
}

export function jsEngine(): UzTranslitWasm {
  return fromExports(engineJs);
}

export const fixtures = JSON.parse(readFileSync(join(WEB, 'test', 'generated', 'fixtures.json'), 'utf8')) as {
  cases: Array<{ id: string; from: string; to: string; in: string; out: string }>;
  roundtrips: Array<{ id: string; from: string; via: string; in: string }>;
  detect: Array<{ in: string; expect: string }>;
  optional: Array<{ feature: string; from: string; to: string; in: string; out: string }>;
};
