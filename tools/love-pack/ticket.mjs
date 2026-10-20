// ticket.mjs
//
// add-partner-love-theme: the love-coupon ticket, on the owner's side. When
// she redeems a coupon the app shows a ticket (QR + text) carrying
//   LASKA1:<couponId>:<yyyyMMddHHmm UTC>:<code>
// where <code> is an HMAC-SHA256 over the pack id, the coupon and the minute,
// keyed by SHA-256("arclove-ticket|" + the pack's seed). The seed is in the
// pack only -- never shown in the app -- so a ticket cannot be made up or
// edited without redeeming the coupon in the app. Keep in step with
// ios/FoodLogCore/Sources/FoodLogCore/Love/LoveTicket.swift (the shared test
// vector is in test.mjs and LoveTicketTests).

import crypto from 'node:crypto';

const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; // Crockford base32

export function ticketCode(seed, packId, couponId, minute) {
  const key = crypto.createHash('sha256').update('arclove-ticket|' + seed).digest();
  const mac = crypto.createHmac('sha256', key).update(`v1|${packId}|${couponId}|${minute}`).digest();
  let bits = 0n;
  for (const byte of mac.subarray(0, 5)) bits = (bits << 8n) | BigInt(byte);
  let out = '';
  for (let i = 7; i >= 0; i--) out += ALPHABET[Number((bits >> BigInt(i * 5)) & 31n)];
  return `${out.slice(0, 4)}-${out.slice(4)}`;
}

export function ticketPayload(seed, packId, couponId, minute) {
  return `LASKA1:${couponId}:${minute}:${ticketCode(seed, packId, couponId, minute)}`;
}

/** { valid, couponId, minute, coupon } -- `coupon` when the pack has it. */
export function verifyTicket(pack, payload) {
  const m = String(payload).trim().toUpperCase().startsWith('LASKA1:')
    ? String(payload).trim().match(/^LASKA1:([A-Za-z0-9._-]+):(\d{12}):([0-9A-Z]{4}-[0-9A-Z]{4})$/i)
    : null;
  if (!m) return { valid: false, reason: 'not a ticket' };
  const [, couponId, minute, code] = m;
  const expected = ticketCode(pack.seed, pack.packId, couponId, minute);
  const coupon = (pack.coupons ?? []).find((c) => c.id === couponId);
  return { valid: expected === code.toUpperCase() && !!coupon, couponId, minute, coupon };
}
