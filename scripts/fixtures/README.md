# Regenerating the web interop fixtures

These scripts run inside a checkout of `spe1020/gratefulday` (they import its code via the `@/` alias).

```sh
# in a gratefulday checkout at the commit you want to capture, with node_modules installed
G=/path/to/grateful_ios; F=$G/Tests/GratefulDayCoreTests/Fixtures
export NODE_OPTIONS=--no-experimental-webstorage   # Node 26+
TZ=America/Chicago npx vite-node $G/scripts/fixtures/gen.ts $F/web_events.json events
for tz in Pacific/Honolulu Pacific/Kiritimati UTC America/New_York Europe/London Asia/Kolkata; do
  TZ=$tz npx vite-node $G/scripts/fixtures/gen.ts /tmp/dates_${tz//\//_}.json dates
done   # then merge the /tmp/dates_*.json files into $F/web_dates.json as {"zones":[...]}
npx vite-node $G/scripts/fixtures/gen.ts $G/Sources/GratefulDayCore/Resources/wisdom.json wisdom
TZ=America/Chicago npx vite-node $G/scripts/fixtures/gen.ts $F/wisdom_samples.json wisdom-samples
node $G/scripts/fixtures/ids.mjs $G/Tests/NostrCoreTests/Resources/nostr_tools_cases.json
```

Private-entry and settings ciphertexts use a random nonce, so regenerated files differ byte-for-byte; the tests compare decrypted text and tags, not ciphertext.
