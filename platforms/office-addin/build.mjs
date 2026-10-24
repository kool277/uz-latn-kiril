#!/usr/bin/env node
/* Writes the add-in manifests from manifest.template.xml and stages the task pane for the web site:
 *   node platforms/office-addin/build.mjs                 → manifest.xml (https://latin.jaybi.uz/office),
 *                                                            manifest-github-pages.xml (https://kool277.github.io/uz-latn-kiril/office)
 *   node platforms/office-addin/build.mjs --stage DIR      → also copies the task pane, its icons and core/js/uztranslit.js to DIR
 *   node platforms/office-addin/build.mjs --check          → exit 1 if a committed manifest differs from the template
 * web/scripts/sync-core.mjs stages it into web/public/office/, so the site serves it at /office/. */
import { copyFileSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
export const SITES = {
  'manifest.xml': 'https://latin.jaybi.uz/office',
  'manifest-github-pages.xml': 'https://kool277.github.io/uz-latn-kiril/office',
};

const host = (type, tab) => `      <Host xsi:type="${type}">
        <DesktopFormFactor>
          <GetStarted>
            <Title resid="GetStarted.Title"/>
            <Description resid="GetStarted.Description"/>
            <LearnMoreUrl resid="LearnMore.Url"/>
          </GetStarted>
          <FunctionFile resid="Commands.Url"/>
          <ExtensionPoint xsi:type="PrimaryCommandSurface">
            <OfficeTab id="${tab}">
              <Group id="UzTranslit.Group">
                <Label resid="Group.Label"/>
                <Icon>
                  <bt:Image size="16" resid="Icon.16"/>
                  <bt:Image size="32" resid="Icon.32"/>
                  <bt:Image size="80" resid="Icon.80"/>
                </Icon>
                <Control xsi:type="Button" id="UzTranslit.Open">
                  <Label resid="Button.Label"/>
                  <Supertip>
                    <Title resid="Button.Label"/>
                    <Description resid="Button.Tooltip"/>
                  </Supertip>
                  <Icon>
                    <bt:Image size="16" resid="Icon.16"/>
                    <bt:Image size="32" resid="Icon.32"/>
                    <bt:Image size="80" resid="Icon.80"/>
                  </Icon>
                  <Action xsi:type="ShowTaskpane">
                    <TaskpaneId>UzTranslit.Taskpane</TaskpaneId>
                    <SourceLocation resid="Taskpane.Url"/>
                  </Action>
                </Control>
              </Group>
            </OfficeTab>
          </ExtensionPoint>
        </DesktopFormFactor>
      </Host>`;

export function manifest(base) {
  const hosts = [host('Document', 'TabHome'), host('Workbook', 'TabHome'), host('Presentation', 'TabHome')].join('\n');
  return readFileSync(join(here, 'manifest.template.xml'), 'utf8')
    .replace(/<!--[\s\S]*?-->\n/, '<!-- generated from manifest.template.xml by build.mjs: do not edit -->\n')
    .replace('{HOSTS}', hosts)
    .replaceAll('{BASE}', base)
    .replaceAll('{DOMAIN}', new URL(base).origin);
}

const args = process.argv.slice(2);
if (args.includes('--check')) {
  const stale = Object.entries(SITES).filter(([f, base]) => readFileSync(join(here, f), 'utf8') !== manifest(base)).map(([f]) => f);
  if (stale.length) { console.log('stale (run node platforms/office-addin/build.mjs):', stale.join(', ')); process.exit(1); }
  console.log('manifests up to date');
} else {
  for (const [f, base] of Object.entries(SITES)) writeFileSync(join(here, f), manifest(base));
  const i = args.indexOf('--stage');
  if (i >= 0) {
    const out = args[i + 1];
    rmSync(out, { recursive: true, force: true });
    mkdirSync(out, { recursive: true });
    for (const f of readdirSync(join(here, 'src'))) copyFileSync(join(here, 'src', f), join(out, f));
    for (const f of readdirSync(join(here, 'assets'))) copyFileSync(join(here, 'assets', f), join(out, f));
    copyFileSync(join(root, 'core', 'js', 'uztranslit.js'), join(out, 'uztranslit.js'));
    for (const f of Object.keys(SITES)) copyFileSync(join(here, f), join(out, f));
    console.log('office add-in staged in', out);
  } else console.log('wrote', Object.keys(SITES).join(', '));
}
