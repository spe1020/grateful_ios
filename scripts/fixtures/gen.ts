// Generates Grateful Day iOS Phase 0 fixtures from the web app's own code at a33f42c.
import { writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { finalizeEvent, getPublicKey } from 'nostr-tools';
import { NSecSigner } from '@nostrify/nostrify';
import { joinNotes, splitNotes, normalizeNotes } from '@/lib/entryNotes';
import { formatDateString, formatDisplayDate, getDayOfYear, getDateFromDayOfYear, getAffirmationForDay } from '@/lib/gratitudeUtils';
import { ENCRYPTED_ALT, ENCRYPTED_TAG, encryptEntryContent } from '@/lib/privacyUtils';
import { buildSettingsEvent, encryptSettings, serializeSettings, parseSettings, reconcile } from '@/lib/appSettings';
import { WISDOM_START_DATE, WISDOM_EXPANDED_START_DATE, WISDOM_ROTATION, getWisdomForDate } from '@/lib/wisdom';
import { DAILY_WISDOM } from '@/lib/data/dailyWisdom';
import { DAILY_AFFIRMATIONS } from '@/lib/data/dailyAffirmations';
import TEACHINGS from '@/lib/data/teachings.json';

const out = process.argv[2];
const mode = process.argv[3] ?? 'events';
const sk = createHash('sha256').update('grateful-day-ios-fixture-key-v1').digest();
const pk = getPublicKey(sk);
const signer = new NSecSigner(sk);

// Mirrors DayDetailDialog.tsx buildEntryEvent at a33f42c (tags are built inline there).
async function entryTemplate(year: number, doy: number, notes: string[], isPrivate: boolean) {
  const date = getDateFromDayOfYear(year, doy);
  const dateString = formatDateString(date);
  const trimmedText = joinNotes(notes);
  const baseTags = [['d', dateString], ['published_at', String(Math.floor(date.getTime() / 1000))], ['day', String(doy)]];
  if (!isPrivate) {
    return { kind: 36669, content: trimmedText, tags: [...baseTags, ['alt', `Daily reflection entry for ${formatDisplayDate(date)} (Day ${doy})`]] };
  }
  const ciphertext = await encryptEntryContent(signer, pk, trimmedText);
  return { kind: 36669, content: ciphertext, tags: [...baseTags, [...ENCRYPTED_TAG], ['alt', ENCRYPTED_ALT]] };
}
const sign = (t: { kind: number; content: string; tags: string[][] }, created_at: number) => finalizeEvent({ ...t, created_at }, sk);

if (mode === 'events') {
  const cases: Record<string, unknown>[] = [];
  const add = async (name: string, year: number, doy: number, notes: string[], isPrivate: boolean, created_at: number, extra: Record<string, unknown> = {}) => {
    const ev = sign(await entryTemplate(year, doy, notes, isPrivate), created_at);
    cases.push({ name, event: ev, plaintext: joinNotes(notes), notes: splitNotes(joinNotes(notes)), isPrivate, ...extra });
    return ev;
  };
  await add('public_single', 2026, 325, ['Morning light on the kitchen table.'], false, 1795280000);
  await add('private_single', 2026, 325, ['A private thank-you to my sister.'], true, 1795280001);
  await add('public_multi', 2026, 326, ['First moment.', 'Second moment,\nwith a line break.', '  Third, trimmed.  '], false, 1795366400);
  await add('private_multi_unicode', 2026, 327, ['Grateful for café ☕ and 🙏', 'Ünïcödé second note'], true, 1795452800);
  const v1 = await add('edited_v1', 2026, 328, ['Draft one.'], false, 1795539200);
  await add('edited_v2', 2026, 328, ['Draft one.', 'Added later.'], false, 1795539300, { replaces: v1.id });
  await add('leap_day', 2028, 60, ['Leap day.'], false, 1835395200);
  // Read-path only: content authored with CRLF by another client (web never writes this).
  const crlf = finalizeEvent({ kind: 36669, created_at: 1795600000, content: 'One\r\n\r\nTwo\r\nstill two\r\r\rThree',
    tags: [['d', '2026-11-25'], ['published_at', String(Math.floor(getDateFromDayOfYear(2026, 329).getTime() / 1000))], ['day', '329'], ['alt', 'crlf']] }, sk);
  cases.push({ name: 'crlf_read_only', event: crlf, notes: splitNotes(crlf.content), isPrivate: false });
  // Kind 5 delete, shape from useDeleteGratitudeEntry.ts at a33f42c.
  const del = finalizeEvent({ kind: 5, content: 'Deleted gratitude entry', created_at: 1795540000,
    tags: [['a', `36669:${pk}:2026-11-24`], ['e', v1.id], ['k', '36669']] }, sk);
  // Settings (30078), via appSettings.ts.
  const settings = { privacyDefault: true, celebratedMilestones: [30, 7], lastSeenNotifications: 1795280000 };
  const sEv = sign(buildSettingsEvent(await encryptSettings(signer, pk, settings)), 1795280100);
  const sMin = sign(buildSettingsEvent(await encryptSettings(signer, pk, { celebratedMilestones: [] })), 1795280050);
  const notesCases = ['', '   ', 'one', 'a\n\nb', 'a\n \t\nb', 'a\nb', '\n\n a \n\n\n b \n', 'x\r\ny', 'x\r\n\r\ny', 'x\r\ry']
    .map((input) => ({ input, split: splitNotes(input), normalized: normalizeNotes(input) }));
  const mergeCases = [
    { local: { celebratedMilestones: [7] }, remote: null },
    { local: { privacyDefault: false, celebratedMilestones: [7, 14], lastSeenNotifications: 500 }, remote: { privacyDefault: true, celebratedMilestones: [30], lastSeenNotifications: 400 } },
    { local: { privacyDefault: true, celebratedMilestones: [] }, remote: { celebratedMilestones: [7] } },
  ].map((c) => ({ ...c, reconciled: reconcile(c.local, c.remote) }));
  const parseCases = ['{"version":1,"privacyDefault":true,"celebratedMilestones":[30,7,7],"lastSeenNotifications":5}',
    'not json', 'null', '{"celebratedMilestones":"nope","privacyDefault":3}', '{"celebratedMilestones":[7,"x",14],"extra":1}']
    .map((json) => ({ json, parsed: parseSettings(json) }));
  writeFileSync(out, JSON.stringify({
    _about: 'Generated from spe1020/gratefulday @ a33f42c by running its own code (entryNotes, gratitudeUtils, privacyUtils, appSettings; 36669 tags mirror DayDetailDialog.tsx buildEntryEvent). Signed with a PUBLIC TEST KEY: secret = sha256("grateful-day-ios-fixture-key-v1"). Never use it for anything real. Generated in TZ=' + (process.env.TZ ?? 'unset') + '.',
    secretKeyHex: Buffer.from(sk).toString('hex'), pubkey: pk,
    entries: cases, deletion: del,
    settings: { event: sEv, plaintextJson: serializeSettings(settings), parsed: settings },
    settingsMinimal: { event: sMin, plaintextJson: serializeSettings({ celebratedMilestones: [] }) },
    notes: notesCases, settingsMerge: mergeCases, settingsParse: parseCases,
  }, null, 2) + '\n');
} else if (mode === 'dates') {
  // Instants -> local d / day / published_at in this process's TZ.
  const instants = [1795269600, 1795305600, 1798761599, 1798761600, 1835395200, 1772323200, 1773536400, 1793516400];
  const rows = instants.map((t) => {
    const local = new Date(t * 1000);
    const doy = getDayOfYear(local);
    const midnight = getDateFromDayOfYear(local.getFullYear(), doy);
    return { instant: t, d: formatDateString(local), day: doy, published_at: Math.floor(midnight.getTime() / 1000),
      alt: `Daily reflection entry for ${formatDisplayDate(midnight)} (Day ${doy})` };
  });
  writeFileSync(out, JSON.stringify({ tz: process.env.TZ, rows }) + '\n');
} else if (mode === 'wisdom') {
  const byId = new Map<string, unknown>();
  for (const it of [...DAILY_WISDOM, ...WISDOM_ROTATION]) byId.set(it.id, it);
  writeFileSync(out, JSON.stringify({
    _about: 'Daily Wisdom data exported from spe1020/gratefulday @ a33f42c (src/lib/wisdom.ts and src/lib/data). Selection: pick the last schedule whose `from` <= the local date (YYYY-MM-DD); index = whole days from `from` (UTC-normalized) mod itemIds.length.',
    version: 1,
    schedules: [
      { from: WISDOM_START_DATE, itemIds: DAILY_WISDOM.map((w) => w.id) },
      { from: WISDOM_EXPANDED_START_DATE, itemIds: WISDOM_ROTATION.map((w) => w.id) },
    ],
    items: [...byId.values()],
  }, null, 1) + '\n');
} else if (mode === 'wisdom-samples') {
  const rows: { date: string; id: string | null }[] = [];
  const d = new Date(2026, 8, 1);
  while (d < new Date(2028, 0, 1)) {
    rows.push({ date: formatDateString(d), id: getWisdomForDate(d)?.id ?? null });
    d.setDate(d.getDate() + 1);
  }
  writeFileSync(out, JSON.stringify({ _about: 'getWisdomForDate at a33f42c for every local date 2026-09-01..2027-12-31 (null = no wisdom item; web falls back to the legacy quote).', rows }) + '\n');
} else if (mode === 'affirmations') {
  // Strides are those in gratitudeUtils.ts getAffirmationForDay; the
  // affirmation-samples fixture pins them against the web function itself.
  // GD_WEB_COMMIT: the gratefulday commit this checkout is at (recorded, required).
  const commit = process.env.GD_WEB_COMMIT;
  if (!commit) throw new Error('set GD_WEB_COMMIT to the gratefulday commit');
  writeFileSync(out, JSON.stringify({
    _about: 'Daily Affirmations exported from spe1020/gratefulday @ ' + commit + ' (src/lib/data/dailyAffirmations.ts). Grateful Day\'s own writing. Selection (getAffirmationForDay): doy = day of year of the local date (1-366), raw = (doy - 1) * stride + year * yearStride, index = ((raw % n) + n) % n over items in array order. itemsSha256 = SHA-256 of the items joined with "\\n" (UTF-8).',
    version: 1,
    sourceCommit: commit,
    rotation: { stride: 53, yearStride: 23 },
    itemsSha256: createHash('sha256').update(DAILY_AFFIRMATIONS.join('\n'), 'utf8').digest('hex'),
    items: DAILY_AFFIRMATIONS,
  }, null, 1) + '\n');
} else if (mode === 'readers-guard') {
  // Hashes only, never text: lets the iOS tests prove no web teaching (future
  // Daily Readers) title, body or quote is in the app bundle. Normalise:
  // lower-case, every run of non-letters/digits becomes one space, trim.
  // Each field gives the hash of its whole normalised text, plus one hash per
  // run of 8 consecutive words. Hash = first 16 hex of SHA-256.
  const norm = (t: string) => t.toLowerCase().normalize('NFKD').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  const h = (t: string) => createHash('sha256').update(t, 'utf8').digest('hex').slice(0, 16);
  const whole = new Set<string>(); const grams = new Set<string>();
  for (const t of TEACHINGS as { title: string; body: string; scriptureQuote?: string }[]) {
    for (const f of [t.title, t.body, t.scriptureQuote ?? '']) {
      const n = norm(f); if (!n) continue;
      whole.add(h(n));
      const w = n.split(' ');
      for (let i = 0; i + 8 <= w.length; i++) grams.add(h(w.slice(i, i + 8).join(' ')));
    }
  }
  writeFileSync(out, JSON.stringify({
    _about: 'Hashes (no text) of every gratefulday teaching title, body and scriptureQuote @ ' + (process.env.GD_WEB_COMMIT ?? 'unset') + ' (src/lib/data/teachings.json, ' + TEACHINGS.length + ' items). See gen.ts readers-guard for the normalisation.',
    gram: 8, whole: [...whole].sort(), grams: [...grams].sort(),
  }) + '\n');
} else if (mode === 'affirmation-samples') {
  // Calls the web's getAffirmationForDay exactly as TodayHero.tsx does.
  const rows: { date: string; index: number }[] = [];
  const d = new Date(2026, 0, 1);
  while (d < new Date(2029, 0, 1)) {
    const line = getAffirmationForDay(getDayOfYear(d), d.getFullYear());
    const index = DAILY_AFFIRMATIONS.indexOf(line);
    if (index < 0 || DAILY_AFFIRMATIONS.lastIndexOf(line) !== index) throw new Error('affirmation not unique: ' + line);
    rows.push({ date: formatDateString(d), index });
    d.setDate(d.getDate() + 1);
  }
  writeFileSync(out, JSON.stringify({ _about: 'getAffirmationForDay(getDayOfYear(d), d.getFullYear()) at ' + (process.env.GD_WEB_COMMIT ?? 'unset') + ' for every local date 2026-01-01..2028-12-31, as an index into affirmations.json items. Generated in TZ=' + (process.env.TZ ?? 'unset') + '.', rows }) + '\n');
}
