export type Script = 'cyr' | 'lat' | 'new';
export type Source = Script | 'auto';

export interface Options {
  /** mark used in Oʻ/Gʻ output; one character or '' (default U+02BB) */
  okina?: string;
  /** mark used for ъ / tutuq output; one character or '' (default U+02BC) */
  tutuq?: string;
  dropHardSignAfterO?: boolean;
  tsFinal?: boolean;
  dictionary?: boolean;
  skipUrls?: boolean;
}

export declare const VERSION: string;
export declare const SCRIPTS: readonly Script[];
export declare const DEFAULTS: Readonly<Required<Options>>;

export declare function instantiate(source: WebAssembly.Module | BufferSource | Response): Promise<UzTranslitWasm>;
/** Wraps the exports of build/uztranslit.engine.js (the engine translated to plain JavaScript). */
export declare function fromExports(exports: object): UzTranslitWasm;

export declare class UzTranslitWasm {
  constructor(instance: WebAssembly.Instance | { exports: object });
  convert(text: string, from: Source, to: Script, options?: Options): string;
  convertSegments(pieces: readonly string[], from: Source, to: Script, options?: Options): { pieces: string[]; from: Script };
  detect(text: string): Script;
  cyrToLat(text: string, options?: Options): string;
  cyrToNew(text: string, options?: Options): string;
  latToCyr(text: string, options?: Options): string;
  newToCyr(text: string, options?: Options): string;
  latToNew(text: string, options?: Options): string;
  newToLat(text: string, options?: Options): string;
}
