import { getEventHash, nip19, getPublicKey } from 'nostr-tools';
import { writeFileSync } from 'node:fs';
const pk = '7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e';
const contents = ['', 'plain', 'quote " backslash \\ slash /', 'line\nbreak\r\ttab\b\f', 'ctrl \u0001\u001f \u007f', 'emoji 🙏 café', 'nul\u0000x', '  '];
const cases = contents.map((content, i) => {
  const ev = { pubkey: pk, created_at: 1700000000 + i, kind: 36669, tags: [['d', '2026-11-21'], ['alt', 'x "y" \n z']], content };
  return { ...ev, id: getEventHash(ev) };
});
const nip19cases = [
  { hex: pk, npub: nip19.npubEncode(pk) },
];
const sk = '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa';
nip19cases.push({ secretHex: sk, nsec: nip19.nsecEncode(Uint8Array.from(Buffer.from(sk, 'hex'))), pubkeyHex: getPublicKey(Uint8Array.from(Buffer.from(sk, 'hex'))) });
writeFileSync(process.argv[2], JSON.stringify({ _about: 'Computed with nostr-tools (getEventHash, nip19) from gratefulday @ a33f42c node_modules.', eventIds: cases, nip19: nip19cases }, null, 1) + '\n');
