import { Paragraph } from '../text-model';
import { ConvertOptions, Converter, FormatId, Script } from '../types';

/**
 * A parsed document: every paragraph to convert (including those of embedded documents) and a writer.
 * The dispatcher detects the source script over all paragraphs, converts them in large batches and then
 * calls finish(); handlers never call the engine themselves.
 */
export interface Prepared {
  format: FormatId;
  mime: string;
  paras: Paragraph[];
  parts: number;
  encoding?: string;
  warnings: string[];
  /** the converted file, or null when nothing changed */
  finish(to: Script): Uint8Array | null;
}

export interface PrepareContext {
  engine: Converter;
  options: ConvertOptions;
  depth: number;
}
