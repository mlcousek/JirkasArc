// test.mjs
//
// add-partner-love-theme: the pack builder's self-test, run by CI's
// `localization` job (plain Node, seconds). Checks that the committed
// sample.arclove is what the builder makes from sample/, and that the
// refusals the app also makes (a duplicated id, an oversized picture) and
// the spoiler allow-list are enforced. The Swift side reads the same
// sample.arclove (LovePackTests), so builder and phone are kept in step.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildPack, buildFolder, pictureHeader, PackError, readAllowlist } from './lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const allowlist = readAllowlist();
const samplePack = JSON.parse(fs.readFileSync(path.join(here, 'sample', 'pack.json'), 'utf8'));
const readSamplePicture = (file) => fs.readFileSync(path.join(here, 'sample', 'images', file));

let failures = 0;
function test(name, body) {
  try {
    body();
    console.log(`ok   ${name}`);
  } catch (error) {
    failures += 1;
    console.error(`FAIL ${name}\n     ${error.message}`);
  }
}

function refused(pack, pattern, readPicture = readSamplePicture) {
  assert.throws(() => buildPack(pack, readPicture, allowlist), (error) => error instanceof PackError && pattern.test(error.message));
}

const clone = () => structuredClone(samplePack);

test('the committed sample.arclove is up to date', () => {
  const built = buildFolder(path.join(here, 'sample'), allowlist);
  const committed = fs.readFileSync(path.join(here, 'sample.arclove'), 'utf8').replace(/\r\n/g, '\n');
  assert.equal(committed, built, 'run: node tools/love-pack/build.mjs --sample');
});

test('the sample pictures are PNGs the phone accepts', () => {
  for (const image of samplePack.images) {
    const header = pictureHeader(readSamplePicture(image.file));
    assert.equal(header?.format, 'png');
    assert.ok(header.width <= 4096 && header.height <= 4096);
  }
});

test('a duplicated id is named', () => {
  const pack = clone();
  pack.daily[3].id = 'd002';
  refused(pack, /"d002" is used twice/);
});

test('an unknown lore tag is refused, naming the picture and the term', () => {
  const pack = clone();
  pack.images[0].lore = ['not-on-the-list'];
  refused(pack, /picture "i001".*"not-on-the-list"/);
});

test('a picture without lore tags is refused', () => {
  const pack = clone();
  delete pack.images[0].lore;
  refused(pack, /picture "i001" needs lore tags/);
});

test('an oversized picture is refused', () => {
  const big = Buffer.concat([readSamplePicture('heart-gradient.png'), Buffer.alloc(2 * 1024 * 1024)]);
  refused(clone(), /picture "i001" is .* MiB/, (file) => (file === 'heart-gradient.png' ? big : readSamplePicture(file)));
});

test('an unknown slot is refused', () => {
  const pack = clone();
  pack.images[1].slots = ['wallpaper'];
  refused(pack, /unknown slot "wallpaper"/);
});

test('an impossible date is refused', () => {
  const pack = clone();
  pack.startDate = '2030-02-30';
  refused(pack, /startDate/);
});

test('every allow-list term is a lowercase slug', () => {
  for (const term of Object.keys(allowlist.terms)) assert.match(term, /^[a-z0-9-]+$/);
  assert.equal(typeof allowlist.seenThrough, 'string');
});

if (failures > 0) {
  console.error(`\n${failures} love-pack test(s) failed`);
  process.exit(1);
}
