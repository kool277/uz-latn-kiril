import { describe, expect, it } from 'vitest';
import type { Script, Source } from '../../src/app/engine/types';
import { fixtures, jsEngine, wasmEngine } from './helpers';

// The web fixture runner (CLAUDE_CODE_PROMPT rule 3): every check in spec/fixtures.json, through both engines
// the web app ships — the WebAssembly module and its plain-JS fallback.
for (const [label, load] of [['wasm', wasmEngine], ['js fallback', async () => jsEngine()]] as const) {
  describe(`spec/fixtures.json via ${label}`, async () => {
    const U = await load();
    it.each(fixtures.cases)('$id $from→$to', c => {
      expect(U.convert(c.in, c.from as Source, c.to as Script)).toBe(c.out);
    });
    it.each(fixtures.roundtrips)('$id roundtrip', r => {
      const there = U.convert(r.in, r.from as Source, r.via as Script);
      expect(U.convert(there, r.via as Source, r.from as Script)).toBe(r.in);
    });
    it.each(fixtures.detect)('detect $in', d => {
      expect(U.detect(d.in)).toBe(d.expect);
    });
    it.each(fixtures.optional)('optional $feature', o => {
      const options = o.feature === 'asciiApostrophe' ? { okina: "'", tutuq: "'" } : { skipUrls: true };
      expect(U.convert(o.in, o.from as Source, o.to as Script, options)).toBe(o.out);
    });
  });
}
