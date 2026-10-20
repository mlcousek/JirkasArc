// verify-ticket.mjs
//
// Checks a love-coupon ticket she shows you (scan its QR code or type the
// line under it):
//
//   node tools/love-pack/verify-ticket.mjs path/to/my-pack "LASKA1:c-dinner:202610201015:ABCD-EFGH"
//
// Prints whether it is genuine, which coupon and when it was redeemed.

import fs from 'node:fs';
import path from 'node:path';
import { verifyTicket } from './ticket.mjs';

const [where, payload] = process.argv.slice(2);
if (!where || !payload) {
  console.error('usage: node tools/love-pack/verify-ticket.mjs <pack folder or pack.json> "<ticket>"');
  process.exit(2);
}
const file = fs.statSync(where).isDirectory() ? path.join(where, 'pack.json') : where;
const pack = JSON.parse(fs.readFileSync(file, 'utf8'));
const result = verifyTicket(pack, payload);
if (!result.valid) {
  console.log('❌ NEPLATNÝ lístek' + (result.coupon === undefined && result.couponId ? ` (kupón "${result.couponId}" v balíčku není)` : ''));
  process.exit(1);
}
const t = result.minute;
const when = new Date(Date.UTC(+t.slice(0, 4), +t.slice(4, 6) - 1, +t.slice(6, 8), +t.slice(8, 10), +t.slice(10, 12)));
console.log(`✅ PLATNÝ lístek: ${result.coupon.title}`);
console.log(`   uplatněno ${when.toLocaleString('cs-CZ', { timeZone: 'Europe/Prague' })}`);
