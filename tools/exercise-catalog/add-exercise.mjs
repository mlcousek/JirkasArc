#!/usr/bin/env node
/**
 * add-exercise.mjs -- add an exercise (with its two pictures) to the app's
 * exercise catalog from the public-domain free-exercise-db (Unlicense,
 * https://github.com/yuhonas/free-exercise-db). See docs/exercise-catalog.md
 * (add-workout-tracker design D5/D6).
 *
 *   node tools/exercise-catalog/add-exercise.mjs search "bulgarian split"
 *   node tools/exercise-catalog/add-exercise.mjs add Split_Squats \
 *       --slug split-squat --en "Split squat" --cs "Dřep s nohou vzadu" \
 *       --aliases "split squat,bulgarian split squat,výpad vzadu" \
 *       --cues-en "Front shin near vertical.|Drop straight down.|Weight over the front foot." \
 *       --cues-cs "Přední holeň svisle.|Klesej přímo dolů.|Váha nad přední nohou."
 *
 * `add` downloads <id>/0.jpg and <id>/1.jpg into ios/GarminFood/Resources/
 * Exercises/<slug>-0.jpg / -1.jpg and appends one entry to ios/FoodLogCore/
 * Sources/FoodLogCore/Resources/exercise-catalog.json. Without --cues-en the
 * database's first three instruction steps are used (English only: the Czech
 * cues then repeat the English until someone translates them). `--video <url>`
 * sets a curated video. It refuses a slug that already exists.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const catalogPath = path.join(root, 'ios/FoodLogCore/Sources/FoodLogCore/Resources/exercise-catalog.json');
const imageDir = path.join(root, 'ios/GarminFood/Resources/Exercises');
const dbBase = 'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/';

function parseFlags(args) {
  const flags = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) flags[args[i].slice(2)] = args[++i];
  }
  return flags;
}

async function loadDb() {
  const response = await fetch(dbBase + 'dist/exercises.json');
  if (!response.ok) throw new Error(`could not load the exercise database (${response.status})`);
  return response.json();
}

const [command, ...rest] = process.argv.slice(2);

if (command === 'search') {
  const words = rest.join(' ').toLowerCase().split(/\s+/).filter(Boolean);
  if (!words.length) throw new Error('usage: search <words>');
  const db = await loadDb();
  const hits = db.filter((e) => words.every((w) => e.name.toLowerCase().includes(w)));
  for (const e of hits.slice(0, 25)) {
    console.log(`${e.id}  |  ${e.name}  |  ${e.primaryMuscles.join(',')}  |  ${e.equipment ?? 'body only'}`);
  }
  console.log(hits.length ? `${hits.length} match(es)` : 'no match -- try fewer or different words');
} else if (command === 'add') {
  const [dbId, ...flagArgs] = rest;
  const f = parseFlags(flagArgs);
  if (!dbId || !f.slug || !f.en) throw new Error('usage: add <db-id> --slug <slug> --en <name> [--cs <name>] [--aliases a,b] [--cues-en "a|b|c"] [--cues-cs "a|b|c"] [--video <url>]');
  if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(f.slug)) throw new Error('--slug must be lowercase letters, digits and hyphens');

  const catalog = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));
  if (catalog.some((e) => e.id === f.slug)) throw new Error(`"${f.slug}" is already in the catalog`);

  const db = await loadDb();
  const source = db.find((e) => e.id === dbId);
  if (!source) throw new Error(`"${dbId}" is not in the database; use: search <words>`);

  const cuesEn = f['cues-en'] ? f['cues-en'].split('|') : source.instructions.slice(0, 3);
  const cuesCs = f['cues-cs'] ? f['cues-cs'].split('|') : cuesEn;
  if (cuesCs.length !== cuesEn.length) throw new Error('--cues-en and --cues-cs need the same number of cues');

  fs.mkdirSync(imageDir, { recursive: true });
  const images = [];
  for (let n = 0; n < Math.min(source.images.length, 2); n++) {
    const response = await fetch(`${dbBase}exercises/${dbId}/${n}.jpg`);
    if (!response.ok) throw new Error(`image ${n} failed (${response.status})`);
    fs.writeFileSync(path.join(imageDir, `${f.slug}-${n}.jpg`), Buffer.from(await response.arrayBuffer()));
    images.push(`${f.slug}-${n}`);
  }
  if (!images.length) throw new Error('the database has no pictures for this exercise');

  catalog.push({
    id: f.slug,
    name: { en: f.en, cs: f.cs ?? f.en },
    aliases: (f.aliases ?? f.en).split(',').map((s) => s.trim()).filter(Boolean),
    cues: cuesEn.map((en, i) => ({ en, cs: cuesCs[i] })),
    images,
    video: f.video ?? null,
  });
  fs.writeFileSync(catalogPath, '[\n' + catalog.map((e) => JSON.stringify(e)).join(',\n') + '\n]\n');
  console.log(`added "${f.slug}" with ${images.length} picture(s). Catalog now has ${catalog.length} exercises.`);
} else {
  console.log('usage: add-exercise.mjs search <words> | add <db-id> --slug ... --en ...');
  process.exit(command ? 1 : 0);
}
