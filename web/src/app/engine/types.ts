export type Script = 'cyr' | 'lat' | 'new';
export type Source = Script | 'auto';

/** Conversion options (SPEC §2); every port uses the same defaults. */
export interface ConvertOptions {
  okina?: string;
  tutuq?: string;
  dropHardSignAfterO?: boolean;
  tsFinal?: boolean;
  dictionary?: boolean;
  skipUrls?: boolean;
}

/** The engine API the format handlers rely on (implemented by core/wasm/uztranslit-wasm.mjs). */
export interface Converter {
  convert(text: string, from: Source, to: Script, options?: ConvertOptions): string;
  convertSegments(pieces: readonly string[], from: Source, to: Script, options?: ConvertOptions): { pieces: string[]; from: Script };
  detect(text: string): Script;
}

export type FormatId =
  | 'text' | 'csv' | 'markdown' | 'json' | 'srt' | 'vtt' | 'ass'
  | 'html' | 'xml' | 'svg' | 'fb2' | 'rtf'
  | 'docx' | 'xlsx' | 'pptx' | 'odt' | 'ods' | 'odp' | 'odg' | 'fodt' | 'fods' | 'fodp' | 'fodg' | 'epub';

export interface DocumentJob {
  name: string;
  bytes: Uint8Array;
  from: Source;
  to: Script;
  options: ConvertOptions;
}

export interface DocumentResult {
  name: string;
  bytes: Uint8Array;
  mime: string;
  format: FormatId;
  /** the source script that was converted (resolved when the job asked for 'auto') */
  from: Script;
  /** text encoding of the input, for text formats */
  encoding?: string;
  stats: { segments: number; changed: number; parts: number };
  /** message keys (see i18n) */
  warnings: string[];
}

export type Progress = (done: number, total: number) => void;

/** A user-facing failure; `code` is an i18n key. */
export class ConversionError extends Error {
  constructor(readonly code: string, detail?: string) {
    super(detail ? `${code}: ${detail}` : code);
  }
}
