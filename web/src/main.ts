import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { App } from './app/app';

interface TrustedTypePolicyFactory {
  createPolicy(name: string, rules: { createScriptURL?: (url: string) => string }): unknown;
}

// Trusted Types (required by the Content-Security-Policy in index.html): the only script URLs this page
// may load are its own bundles — the conversion workers and the service worker. HTML and script strings
// get no policy at all, so any innerHTML/eval-style sink stays blocked.
const tt = (globalThis as { trustedTypes?: TrustedTypePolicyFactory }).trustedTypes;
tt?.createPolicy('default', {
  createScriptURL(url: string): string {
    const u = new URL(url, document.baseURI);
    if (u.origin === location.origin && u.pathname.endsWith('.js')) return u.href;
    throw new TypeError(`Blocked script URL: ${url}`);
  }
});

bootstrapApplication(App, appConfig)
  .catch((err) => console.error(err));
