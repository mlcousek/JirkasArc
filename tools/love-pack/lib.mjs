// lib.mjs
//
// add-partner-love-theme D1/D11: the love pack's rules on the owner's side.
// `build.mjs` turns a folder (pack.json + images/) into the `.arclove` file
// he AirDrops to her phone; this module holds the checks so the builder and
// its self-test share them.
//
// Keep in step with ios/FoodLogCore/Sources/FoodLogCore/Love/LovePack.swift
// (`LovePackReader`): the same limits, ids, dates, slots and picture checks,
// so a pack the builder accepts is a pack the phone accepts. On top, the
// builder enforces the spoiler allow-list (lore-allowlist.json), which the
// phone does not: every lore tag must be on it.
//
// No dependencies; Node 20.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const LIMITS = {
  maxFileBytes: 40 * 1024 * 1024,
  maxTextLength: 600,
  maxShortTextLength: 120,
  maxItemsPerList: 2000,
  maxPictures: 80,
  maxPictureBytes: 2 * 1024 * 1024,
  maxPictureSide: 4096,
  maxIdLength: 64,
  maxCouponPrice: 10000,
};

const RANKS = ['akademie', 'genin', 'chunin', 'jonin', 'anbu', 'sannin', 'kage'];
const ID = /^[A-Za-z0-9._-]+$/;

export class PackError extends Error {}

const fail = (message) => { throw new PackError(message); };

/** Characters as Swift counts them (grapheme clusters). */
function length(text) {
  return [...new Intl.Segmenter('cs', { granularity: 'grapheme' }).segment(text)].length;
}

function nonEmpty(value) {
  return typeof value === 'string' && value.trim() !== '' ? value : null;
}

export function isValidId(id) {
  return typeof id === 'string' && id.length > 0 && id.length <= LIMITS.maxIdLength && ID.test(id);
}

export function isValidDay(day) {
  if (typeof day !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(day)) return false;
  const [y, m, d] = day.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return date.getUTCFullYear() === y && date.getUTCMonth() === m - 1 && date.getUTCDate() === d;
}

export function isKnownSlot(slot) {
  if (['loveCard', 'messageBoxHeader', 'pictureOfDay', 'emptyState'].includes(slot)) return true;
  if (slot.startsWith('rankEmblem:')) return RANKS.includes(slot.slice('rankEmblem:'.length));
  if (slot.startsWith('badge:')) return isValidId(slot.slice('badge:'.length));
  return false;
}

/** { format: 'png' | 'jpeg', width, height } or null. */
export function pictureHeader(bytes) {
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length >= 24 && png.every((b, i) => bytes[i] === b) && bytes.toString('latin1', 12, 16) === 'IHDR') {
    return { format: 'png', width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
  }
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    let i = 2;
    while (i + 4 <= bytes.length) {
      if (bytes[i] !== 0xff) return null;
      const marker = bytes[i + 1];
      if (marker === 0xff) { i += 1; continue; }
      if (marker === 0xd8 || (marker >= 0xd0 && marker <= 0xd7) || marker === 0x01) { i += 2; continue; }
      if (marker === 0xd9 || marker === 0xda) return null;
      const segment = bytes.readUInt16BE(i + 2);
      if (segment < 2) return null;
      if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) {
        if (i + 9 > bytes.length) return null;
        return { format: 'jpeg', height: bytes.readUInt16BE(i + 5), width: bytes.readUInt16BE(i + 7) };
      }
      i += 2 + segment;
    }
  }
  return null;
}

function checkList(name, items) {
  if (!Array.isArray(items)) fail(`${name} is not a list`);
  if (items.length > LIMITS.maxItemsPerList) fail(`${name} has more than ${LIMITS.maxItemsPerList} items`);
  const seen = new Set();
  for (const item of items) {
    const id = item?.id;
    if (!nonEmpty(id)) fail(`an item of ${name} has no id`);
    if (!isValidId(id)) fail(`${name}: the id "${id}" may only use letters, digits, ".", "_" and "-" (at most ${LIMITS.maxIdLength})`);
    if (seen.has(id)) fail(`${name}: the id "${id}" is used twice`);
    seen.add(id);
  }
}

function checkLore(where, tags, allowlist) {
  if (tags === undefined) return;
  if (!Array.isArray(tags)) fail(`${where}: lore must be a list`);
  for (const tag of tags) {
    if (!Object.hasOwn(allowlist.terms, tag)) {
      fail(`${where}: the lore tag "${tag}" is not on tools/love-pack/lore-allowlist.json (seen through ${allowlist.seenThrough})`);
    }
  }
}

export function readAllowlist(file = path.join(path.dirname(fileURLToPath(import.meta.url)), 'lore-allowlist.json')) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

/**
 * Validates a pack (pack.json's object plus the picture bytes by file name)
 * and returns the `.arclove` object. Throws PackError naming the first
 * problem, in the same order as the app checks.
 */
export function buildPack(pack, readPicture, allowlist) {
  if (pack?.format !== 'love-pack') fail('format must be "love-pack"');
  if (pack.version !== 1) fail('version must be 1');
  for (const field of ['packId', 'nickname', 'startDate', 'seed']) {
    if (!nonEmpty(pack[field])) fail(`${field} is missing`);
  }
  if (!isValidId(pack.packId)) fail(`packId "${pack.packId}" may only use letters, digits, ".", "_" and "-"`);
  if (length(pack.nickname) > LIMITS.maxShortTextLength) fail('nickname is too long');
  if (pack.signature !== undefined && (typeof pack.signature !== 'string' || length(pack.signature) > LIMITS.maxShortTextLength)) fail('signature is too long');
  if (!isValidDay(pack.startDate)) fail(`startDate "${pack.startDate}" is not a yyyy-MM-dd date`);
  if (length(pack.seed) > LIMITS.maxShortTextLength) fail('seed is too long');
  if (pack.daily === undefined) fail('daily is missing');
  if (!Array.isArray(pack.daily) || pack.daily.length === 0) fail('daily has no messages');

  checkList('daily', pack.daily);
  for (const item of pack.daily) {
    if (!nonEmpty(item.text)) fail(`daily "${item.id}" has no text`);
    if (length(item.text) > LIMITS.maxTextLength) fail(`daily "${item.id}" is longer than ${LIMITS.maxTextLength} characters`);
    checkLore(`daily "${item.id}"`, item.lore, allowlist);
  }

  const openWhen = pack.openWhen ?? [];
  checkList('openWhen', openWhen);
  for (const item of openWhen) {
    if (!nonEmpty(item.title) || !nonEmpty(item.text)) fail(`openWhen "${item.id}" needs a title and a text`);
    if (length(item.title) > LIMITS.maxShortTextLength || length(item.text) > LIMITS.maxTextLength) fail(`openWhen "${item.id}" is too long`);
    checkLore(`openWhen "${item.id}"`, item.lore, allowlist);
  }

  const coupons = pack.coupons ?? [];
  checkList('coupons', coupons);
  for (const item of coupons) {
    if (!nonEmpty(item.title)) fail(`coupon "${item.id}" has no title`);
    if (length(item.title) > LIMITS.maxShortTextLength) fail(`coupon "${item.id}" is too long`);
    if (!Number.isInteger(item.price) || item.price < 1 || item.price > LIMITS.maxCouponPrice) fail(`coupon "${item.id}" needs a price from 1 to ${LIMITS.maxCouponPrice}`);
  }

  if (pack.countdown !== undefined) {
    if (!isValidDay(pack.countdown?.date)) fail('countdown.date is not a yyyy-MM-dd date');
    if (!nonEmpty(pack.countdown.title)) fail('countdown has no title');
  }

  const images = pack.images ?? [];
  if (!Array.isArray(images)) fail('images is not a list');
  if (images.length > LIMITS.maxPictures) fail(`at most ${LIMITS.maxPictures} pictures (this pack has ${images.length})`);
  checkList('images', images);
  const wireImages = [];
  for (const item of images) {
    if (!nonEmpty(item.file)) fail(`picture "${item.id}" names no file`);
    const bytes = readPicture(item.file);
    if (!bytes) fail(`picture "${item.id}": images/${item.file} does not exist`);
    if (bytes.length > LIMITS.maxPictureBytes) fail(`picture "${item.id}" is ${(bytes.length / 1048576).toFixed(1)} MiB; at most 2 MiB -- make it smaller`);
    const header = pictureHeader(bytes);
    if (!header) fail(`picture "${item.id}" is not a PNG or a JPEG`);
    if (header.width < 1 || header.height < 1 || header.width > LIMITS.maxPictureSide || header.height > LIMITS.maxPictureSide) {
      fail(`picture "${item.id}" is ${header.width}x${header.height}; at most ${LIMITS.maxPictureSide} px a side`);
    }
    const slots = item.slots ?? [];
    for (const slot of slots) {
      if (!isKnownSlot(slot)) fail(`picture "${item.id}": unknown slot "${slot}"`);
    }
    if (!Array.isArray(item.lore)) fail(`picture "${item.id}" needs lore tags ([] when it shows nothing from the series)`);
    checkLore(`picture "${item.id}"`, item.lore, allowlist);
    wireImages.push({ id: item.id, slots, lore: item.lore, data: bytes.toString('base64') });
  }

  const out = {
    format: 'love-pack',
    version: 1,
    packId: pack.packId,
    nickname: pack.nickname,
    signature: pack.signature ?? '',
    startDate: pack.startDate,
    seed: pack.seed,
    daily: pack.daily,
    openWhen,
    coupons,
    ...(pack.countdown !== undefined ? { countdown: pack.countdown } : {}),
    images: wireImages,
  };
  const text = JSON.stringify(out, null, 1) + '\n';
  if (Buffer.byteLength(text) > LIMITS.maxFileBytes) {
    fail(`the pack would be ${(Buffer.byteLength(text) / 1048576).toFixed(1)} MiB; at most 40 MiB -- use fewer or smaller pictures`);
  }
  return text;
}

/** Builds a pack folder (pack.json + images/) into the `.arclove` text. */
export function buildFolder(folder, allowlist = readAllowlist()) {
  const packFile = path.join(folder, 'pack.json');
  if (!fs.existsSync(packFile)) fail(`${packFile} does not exist`);
  let pack;
  try {
    pack = JSON.parse(fs.readFileSync(packFile, 'utf8'));
  } catch (error) {
    fail(`pack.json is not valid JSON: ${error.message}`);
  }
  const readPicture = (file) => {
    const resolved = path.join(folder, 'images', file);
    if (path.relative(path.join(folder, 'images'), resolved).startsWith('..')) return null;
    return fs.existsSync(resolved) ? fs.readFileSync(resolved) : null;
  };
  return buildPack(pack, readPicture, allowlist);
}
