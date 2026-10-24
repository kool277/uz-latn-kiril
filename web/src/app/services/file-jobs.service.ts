import { computed, inject, Injectable, signal } from '@angular/core';
import { safeFileName } from '../engine/names';
import { ConversionError } from '../engine/types';
import { EngineService, FileOutcome } from './engine.service';
import { SettingsService } from './settings.service';

export type JobStatus = 'queued' | 'running' | 'done' | 'error' | 'cancelled';

let nextId = 0;

export class FileJob {
  readonly id = ++nextId;
  readonly status = signal<JobStatus>('queued');
  readonly progress = signal(0);
  readonly outcome = signal<FileOutcome | null>(null);
  readonly error = signal<{ code: string; detail: string } | null>(null);
  /** the settings the current result was made with */
  key = '';
  cancel: (() => void) | null = null;

  constructor(readonly file: File) {}
}

export function saveBlob(blob: Blob, name: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = safeFileName(name);
  a.rel = 'noopener';
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}

/** The batch of files on the Files tab. */
@Injectable({ providedIn: 'root' })
export class FileJobsService {
  private readonly engine = inject(EngineService);
  private readonly settings = inject(SettingsService);

  readonly jobs = signal<FileJob[]>([]);
  readonly done = computed(() => this.jobs().filter(j => j.status() === 'done'));
  readonly busy = computed(() => this.jobs().some(j => j.status() === 'queued' || j.status() === 'running'));
  /** finished results made with other settings than the current ones */
  readonly stale = computed(() => this.done().some(j => j.key !== this.settings.key()));
  readonly zipping = signal(false);

  add(files: Iterable<File>): void {
    const added = [...files].map(f => new FileJob(f));
    if (!added.length) return;
    this.jobs.update(list => [...list, ...added]);
    for (const j of added) this.start(j);
  }

  start(job: FileJob): void {
    job.cancel?.();
    job.status.set('queued');
    job.progress.set(0);
    job.error.set(null);
    job.key = this.settings.key();
    const run = this.engine.convertFile(job.file, this.settings.from(), this.settings.to(), this.settings.options(), p => {
      if (job.status() === 'queued') job.status.set('running');
      job.progress.set(p);
    });
    job.cancel = run.cancel;
    run.promise.then(
      outcome => {
        job.outcome.set(outcome);
        job.progress.set(1);
        job.status.set('done');
      },
      (e: unknown) => {
        const code = e instanceof ConversionError ? e.code : 'err.internal';
        job.status.set(code === 'err.cancelled' ? 'cancelled' : 'error');
        job.error.set({ code, detail: e instanceof Error ? e.message : String(e) });
      }
    ).finally(() => { job.cancel = null; });
  }

  cancel(job: FileJob): void {
    job.cancel?.();
  }

  remove(job: FileJob): void {
    job.cancel?.();
    this.jobs.update(list => list.filter(j => j !== job));
  }

  clear(): void {
    for (const j of this.jobs()) j.cancel?.();
    this.jobs.set([]);
  }

  reconvertAll(): void {
    for (const j of this.jobs()) if (j.status() !== 'running' && j.status() !== 'queued') this.start(j);
  }

  download(job: FileJob): void {
    const o = job.outcome();
    if (o) saveBlob(o.blob, o.name);
  }

  async downloadAll(): Promise<void> {
    const done = this.done();
    if (!done.length) return;
    if (done.length === 1) { this.download(done[0]); return; }
    this.zipping.set(true);
    try {
      const used = new Set<string>();
      const files = await Promise.all(done.map(async j => {
        const o = j.outcome()!;
        let name = safeFileName(o.name), k = 1;
        while (used.has(name)) name = safeFileName(o.name).replace(/(\.[^.]+)?$/, m => ` (${++k})${m}`);
        used.add(name);
        return { name, data: new Uint8Array(await o.blob.arrayBuffer()) };
      }));
      const zip = await this.engine.zip(files).promise;
      saveBlob(new Blob([zip as BlobPart], { type: 'application/zip' }), `uztranslit-${this.settings.to()}.zip`);
    } finally {
      this.zipping.set(false);
    }
  }
}
