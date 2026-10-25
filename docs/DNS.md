# latin.jaybi.uz on GitHub Pages

The site is built and published by `.github/workflows/deploy-pages.yml` after CI passes on `main`.
It is served from `https://latin.jaybi.uz/` (before the custom domain: `https://kool277.github.io/uz-latn-kiril/`).
The build targets the root path `/` whenever `web/public/CNAME` names a domain, and otherwise the base path GitHub
Pages reports (`/uz-latn-kiril/`). Delete `web/public/CNAME` to publish on the github.io address only.

## 1. DNS (at the registrar of jaybi.uz)

| Name    | Type  | Value               | TTL  |
|---------|-------|---------------------|------|
| `latin` | CNAME | `kool277.github.io.` | 3600 |

Check it: `dig +short latin.jaybi.uz CNAME` → `kool277.github.io.`

Optional but recommended, against domain takeover: verify `jaybi.uz` for the account under
*GitHub ▸ Settings ▸ Pages ▸ Verified domains* (a TXT record `_github-pages-challenge-kool277.jaybi.uz`).

## 2. Custom domain in the repository

*Settings ▸ Pages*: Source **GitHub Actions**, Custom domain `latin.jaybi.uz`, Save. Or with the CLI:

```bash
gh api -X PUT repos/kool277/uz-latn-kiril/pages -f cname=latin.jaybi.uz
```

GitHub then checks DNS and requests a certificate (minutes, at most a day).

## 3. HTTPS

Once the certificate is issued, tick **Enforce HTTPS** (or `gh api -X PUT repos/kool277/uz-latn-kiril/pages -F https_enforced=true`).

## 4. Redeploy

Run *Actions ▸ Deploy latin.jaybi.uz ▸ Run workflow* once, so the site is rebuilt for the root path `/`.
Check: `curl -sI https://latin.jaybi.uz/ | head -1` → `HTTP/2 200`.

## Notes

- With Actions deployments GitHub ignores a `CNAME` file; `web/public/CNAME` still records the domain and keeps
  working if the site is ever published from a branch. Keep it.
- Everything the site loads is on its own origin (no CDNs, no analytics); the Content-Security-Policy in
  `web/src/index.html` blocks anything else, so a new third-party resource needs a CSP change on purpose.
