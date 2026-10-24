import { fromExports, instantiate, UzTranslitWasm } from '../../generated/uztranslit-wasm.js';

export type EngineKind = 'wasm' | 'js';

/**
 * The WebAssembly engine, or — where WebAssembly is switched off (iOS Lockdown Mode, hardened browsers) —
 * the same engine translated to JavaScript by wasm2js. Both pass the same conformance suite.
 */
export async function createEngine(source: WebAssembly.Module | Response | null): Promise<{ engine: UzTranslitWasm; kind: EngineKind }> {
  if (source && typeof WebAssembly === 'object') {
    try {
      return { engine: await instantiate(source), kind: 'wasm' };
    } catch {
      // fall through to the JavaScript build
    }
  }
  const js = await import('../../generated/uztranslit-engine.js');
  return { engine: fromExports(js), kind: 'js' };
}
