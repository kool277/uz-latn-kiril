import { Script } from './types';

/** "hisobot.docx" → "hisobot-new.docx" */
export function outputName(name: string, to: Script): string {
  const m = /^(.*?)(\.[^./\\]+)?$/.exec(name)!;
  return `${m[1] || 'natija'}-${to}${m[2] ?? ''}`;
}

/** A file name that is safe to offer for download on any OS. */
export function safeFileName(name: string): string {
  const cleaned = name.replace(/[\u0000-\u001f\u007f<>:"/\\|?*]+/g, '_').replace(/^[\s.]+|[\s.]+$/g, '').slice(0, 180);
  return cleaned || 'natija';
}
