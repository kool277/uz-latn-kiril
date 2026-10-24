import { Component, computed, inject, signal } from '@angular/core';
import { ACCEPTED_EXTENSIONS } from '../engine/accepted';
import { MAX_FILE_BYTES } from '../services/engine.service';
import { FileJob, FileJobsService } from '../services/file-jobs.service';
import { I18nService } from '../services/i18n.service';

/** Drop zone and the list of converted files. */
@Component({
  selector: 'app-file-converter',
  templateUrl: './file-converter.html',
  styleUrl: './file-converter.css'
})
export class FileConverter {
  protected readonly jobs = inject(FileJobsService);
  protected readonly i18n = inject(I18nService);
  protected readonly accept = ACCEPTED_EXTENSIONS.join(',');
  protected readonly maxMb = MAX_FILE_BYTES / 1024 / 1024;
  protected readonly over = signal(false);
  protected readonly summary = computed(() =>
    this.i18n.t('files.summary', { done: this.jobs.done().length, total: this.jobs.jobs().length }));

  protected onDragOver(ev: DragEvent): void {
    if (!ev.dataTransfer?.types.includes('Files')) return;
    ev.preventDefault();
    ev.dataTransfer.dropEffect = 'copy';
    this.over.set(true);
  }

  protected onDrop(ev: DragEvent): void {
    ev.preventDefault();
    ev.stopPropagation();
    this.over.set(false);
    if (ev.dataTransfer?.files.length) this.jobs.add(ev.dataTransfer.files);
  }

  protected onPick(ev: Event): void {
    const input = ev.target as HTMLInputElement;
    if (input.files?.length) this.jobs.add(input.files);
    input.value = '';
  }

  protected ext(name: string): string {
    const m = /\.([^.]+)$/.exec(name);
    return m ? m[1].toLowerCase().slice(0, 5) : '?';
  }

  protected size(bytes: number): string {
    const t = this.i18n;
    if (bytes < 1024) return `${t.num(bytes)} ${t.t('unit.b')}`;
    if (bytes < 1024 * 1024) return `${t.num(bytes / 1024, 1)} ${t.t('unit.kb')}`;
    return `${t.num(bytes / 1024 / 1024, 1)} ${t.t('unit.mb')}`;
  }

  protected name(script: string): string {
    return this.i18n.t('name.' + script);
  }

  protected percent(j: FileJob): number | null {
    const p = j.progress();
    return p > 0 && p < 1 ? p : null;
  }
}
