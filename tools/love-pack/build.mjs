// build.mjs
//
// add-partner-love-theme D1: builds the love pack the owner AirDrops to her
// phone. Run it on a folder kept OUTSIDE this repository (his notes vault):
//
//   my-pack/
//     pack.json      texts, ids, settings (see tools/love-pack/README.md)
//     images/        PNG or JPEG pictures named in pack.json
//
//   node tools/love-pack/build.mjs path/to/my-pack            -> my-pack.arclove
//   node tools/love-pack/build.mjs path/to/my-pack --out x.arclove
//
// Every check the phone makes is made here first, plus the spoiler
// allow-list (every lore tag on lore-allowlist.json). Exits non-zero naming
// the first problem.
//
// `--sample` builds the synthetic sample (tools/love-pack/sample/) and, with
// `--check`, fails when the committed sample.arclove is out of date (CI).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildFolder, PackError } from './lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const option = (name) => {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
};

const sample = flag('--sample');
const folder = sample ? path.join(here, 'sample') : args.find((a) => !a.startsWith('--') && a !== option('--out'));
if (!folder) {
  console.error('usage: node tools/love-pack/build.mjs <pack folder> [--out file.arclove]');
  process.exit(2);
}
const out = sample ? path.join(here, 'sample.arclove') : (option('--out') ?? `${path.resolve(folder)}.arclove`);

try {
  const text = buildFolder(folder);
  if (flag('--check')) {
    const current = fs.existsSync(out) ? fs.readFileSync(out, 'utf8').replace(/\r\n/g, '\n') : '';
    if (current !== text) {
      console.error(`${path.relative(process.cwd(), out)} is out of date -- run: node tools/love-pack/build.mjs --sample`);
      process.exit(1);
    }
    console.log(`${path.relative(process.cwd(), out)} is up to date`);
  } else {
    fs.writeFileSync(out, text);
    const pack = JSON.parse(text);
    console.log(`${out}: ${pack.daily.length} messages, ${pack.images.length} pictures, ${(Buffer.byteLength(text) / 1048576).toFixed(2)} MiB`);
  }
} catch (error) {
  if (error instanceof PackError) {
    console.error(`love pack refused: ${error.message}`);
    process.exit(1);
  }
  throw error;
}
