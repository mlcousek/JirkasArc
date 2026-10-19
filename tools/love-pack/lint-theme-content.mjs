// lint-theme-content.mjs
//
// add-partner-love-theme D11: the no-spoiler lint for the partner theme's
// own Czech table (ios/GarminFood/PartnerTheme/Resources/partner-theme.cs.json),
// run by CI's `localization` job.
//
//   1. every `lore` tag is on tools/love-pack/lore-allowlist.json;
//   2. an entry WITHOUT lore tags may not contain a capitalised word in the
//      middle of a sentence -- the likely sign of a forgotten tag on a name.
//      It catches a missing tag; it does not judge meaning (the owner's
//      review of the allow-list does that).
//
// An allow-list, never a deny-list: nothing here names what comes later.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readAllowlist } from './lib.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const tableFile = process.argv[2] ?? path.join(root, 'ios', 'GarminFood', 'PartnerTheme', 'Resources', 'partner-theme.cs.json');
const allowlist = readAllowlist();
const table = JSON.parse(fs.readFileSync(tableFile, 'utf8'));

/** Capitalised words that may stand mid-sentence without a tag. */
const ordinary = new Set(['ANO', 'OK']);
const TEXT_FIELDS = ['text', 'title', 'body', 'description', 'name'];

const problems = [];

/** Words that start with a capital and are not at a sentence start. */
export function midSentenceCapitals(text) {
  const tokens = text.replace(/\{[a-z]+\}/g, 'x').split(/\s+/).filter(Boolean);
  const found = [];
  let atStart = true;
  for (const raw of tokens) {
    const opensQuote = /^[„“"‚'(«]/.test(raw);
    const word = raw.replace(/^[^\p{L}]+/u, '').replace(/[^\p{L}]+$/u, '');
    const hasLetters = /\p{L}/u.test(raw);
    if (!hasLetters) {
      // An emoji or a dash between two sentences.
      atStart = atStart || /[–—]/.test(raw) || /\p{Extended_Pictographic}/u.test(raw);
      continue;
    }
    if (!atStart && !opensQuote && /^\p{Lu}/u.test(word) && !ordinary.has(word)) found.push(word);
    atStart = /[.!?:…]["“”»)]?$/.test(raw);
  }
  return found;
}

function visit(node, where) {
  if (Array.isArray(node)) {
    node.forEach((item, index) => visit(item, `${where}[${index}]`));
    return;
  }
  if (node === null || typeof node !== 'object') return;
  if ('lore' in node) {
    const tags = node.lore;
    if (!Array.isArray(tags)) problems.push(`${where}: lore must be a list`);
    for (const tag of tags ?? []) {
      if (!Object.hasOwn(allowlist.terms, tag)) {
        problems.push(`${where}: the lore tag "${tag}" is not on lore-allowlist.json (seen through ${allowlist.seenThrough})`);
      }
    }
    if (Array.isArray(tags) && tags.length === 0) {
      for (const field of TEXT_FIELDS) {
        if (typeof node[field] !== 'string') continue;
        const capitals = midSentenceCapitals(node[field]);
        if (capitals.length) problems.push(`${where}.${field}: "${capitals.join('", "')}" looks like a name but the entry has no lore tags`);
      }
    }
  }
  for (const [key, value] of Object.entries(node)) {
    if (key !== 'lore') visit(value, where ? `${where}.${key}` : key);
  }
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  visit(table, '');
  if (problems.length) {
    for (const problem of problems) console.error(`partner-theme.cs.json ${problem}`);
    console.error(`\n${problems.length} problem(s): tag the entry with lore terms from tools/love-pack/lore-allowlist.json, or reword it.`);
    process.exit(1);
  }
  console.log('partner theme content: every lore tag is on the allow-list, no untagged names');
}
