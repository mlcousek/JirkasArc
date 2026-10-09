#!/usr/bin/env node
/**
 * pseudo-localize.mjs — makes every Czech string 40 % longer, in place, for
 * a throwaway truncation build (add-localization task 6.3).
 *
 * Why this exists: Xcode's "double-length pseudo-language" scheme option
 * needs a Mac. Instead CI runs this on its own checkout just before the
 * Xcode build (`.github/workflows/build.yml`, a manual run with
 * `pseudo_czech` ticked), and the resulting .ipa is sideloaded on a phone
 * set to Czech. Every Czech string then reads "[Dnes ~~~~]": the brackets
 * show where a string is cut off, the tildes add the 40 % that a longer
 * translation might need (docs/localization-analysis.md §5).
 *
 * Never commit its output: it rewrites the Czech of
 *   - ios/GarminFood/Resources/Localizable.xcstrings and InfoPlist.xcstrings,
 *   - ios/GarminFoodWidget/Resources/*.xcstrings,
 *   - every package's Resources/cs.lproj/*.strings and *.stringsdict.
 * AppShortcuts.xcstrings is left alone (Siri phrases, not screen text).
 * Format specifiers stay as they are, so `node tools/check-localizations.mjs`
 * still passes on the output; only text around them grows.
 *
 * Usage: node tools/pseudo-localize.mjs [--root <dir>]   (default: repo root)
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const args = process.argv.slice(2);
const rootArg = args.indexOf('--root');
const root = rootArg >= 0 ? path.resolve(args[rootArg + 1]) : path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ios = path.join(root, 'ios');

// %lld, %1$@, %.1f, %%, %#@minutes@ -- never counted, never touched.
const SPECIFIER = /%#@[^@]+@|%(\d+\$)?[-+ #0]*(\d+|\*)?(\.\d+)?(hh|h|ll|l|q|L|z|t|j)?[@dDuUxXoOfeEgGcCsSpaAF%]/g;

export function pseudo(text) {
  if (text.trim() === '') return text;
  const visible = text.replace(SPECIFIER, '').replace(/\\./g, '.').length;
  return `[${text} ${'~'.repeat(Math.max(1, Math.ceil(visible * 0.4)))}]`;
}

function walkCs(node) {
  if (Array.isArray(node)) { node.forEach(walkCs); return; }
  if (!node || typeof node !== 'object') return;
  if (node.stringUnit && typeof node.stringUnit.value === 'string') node.stringUnit.value = pseudo(node.stringUnit.value);
  for (const value of Object.values(node)) walkCs(value);
}

function catalog(file) {
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));
  let n = 0;
  for (const entry of Object.values(data.strings ?? {})) {
    const cs = entry.localizations?.cs;
    if (cs) { walkCs(cs); n++; }
  }
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
  return n;
}

// "key" = "value"; -- only the value changes; escapes inside it are kept.
function strings(file) {
  let n = 0;
  const out = fs.readFileSync(file, 'utf8').replace(/^(\s*"(?:[^"\\]|\\.)*"\s*=\s*")((?:[^"\\]|\\.)*)("\s*;)/gm, (_, head, value, tail) => {
    n++;
    return head + pseudo(value) + tail;
  });
  fs.writeFileSync(file, out);
  return n;
}

// Every <string> except the two plural-rule type markers.
function stringsdict(file) {
  let n = 0;
  const out = fs.readFileSync(file, 'utf8').replace(/(<key>([^<]*)<\/key>\s*<string>)([^<]*)(<\/string>)/g, (match, head, key, value, tail) => {
    if (key === 'NSStringFormatSpecTypeKey' || key === 'NSStringFormatValueTypeKey') return match;
    n++;
    return head + pseudo(value) + tail;
  });
  fs.writeFileSync(file, out);
  return n;
}

function* files(dir, test) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'build' || entry.name.startsWith('.')) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) yield* files(full, test);
    else if (test(full)) yield full;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const rel = (f) => path.relative(root, f).split(path.sep).join('/');
  for (const f of files(ios, (f) => f.endsWith('.xcstrings') && !f.endsWith('AppShortcuts.xcstrings'))) console.log(`${rel(f)}: ${catalog(f)} keys`);
  for (const f of files(ios, (f) => /[\\/]cs\.lproj[\\/][^\\/]+\.strings$/.test(f))) console.log(`${rel(f)}: ${strings(f)} strings`);
  for (const f of files(ios, (f) => /[\\/]cs\.lproj[\\/][^\\/]+\.stringsdict$/.test(f))) console.log(`${rel(f)}: ${stringsdict(f)} strings`);
  console.log('Czech is now pseudo-localized (+40 %). Do not commit this.');
}
