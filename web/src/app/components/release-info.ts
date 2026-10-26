import { InjectionToken } from '@angular/core';
import { RELEASE } from '../../generated/release';
import type { MessageKey } from '../services/i18n.service';

/** The latest published GitHub release, as deploy-pages.yml found it (scripts/sync-core.mjs). */
export interface ReleaseInfo {
  tag: string;
  files: { name: string; size: number }[];
}

export const RELEASE_INFO = new InjectionToken<ReleaseInfo | null>('latest release', { factory: () => RELEASE });

/** The installable files of a release, in the order the download panel shows them (release.yml names them). */
const APPS: readonly { pattern: RegExp; label: MessageKey }[] = [
  { pattern: /-Windows-x64-setup\.exe$/, label: 'dl.appWindows' },
  { pattern: /-macOS\.dmg$/, label: 'dl.appMac' },
  { pattern: /\.AppImage$/, label: 'dl.appLinux' },
  { pattern: /-android\.apk$/, label: 'dl.appAndroid' },
  { pattern: /-Office-Setup\.exe$/, label: 'dl.appOffice' }
];

export interface AppDownload {
  label: MessageKey;
  url: string;
  size: number;
}

/** Only files the release really has get a button: a missing build never becomes a broken link. */
export function appDownloads(release: ReleaseInfo | null, repo: string): AppDownload[] {
  if (!release) return [];
  const out: AppDownload[] = [];
  for (const app of APPS) {
    const file = release.files.find(f => app.pattern.test(f.name));
    if (file) out.push({ label: app.label, url: releaseFileUrl(release, repo, file.name), size: file.size });
  }
  return out;
}

export function releaseFileUrl(release: ReleaseInfo, repo: string, name: string): string {
  return `${repo}/releases/download/${encodeURIComponent(release.tag)}/${encodeURIComponent(name)}`;
}
