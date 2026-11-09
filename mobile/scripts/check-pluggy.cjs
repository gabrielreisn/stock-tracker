const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

const requests = [];
let failToken = false;
const entry = path.resolve(__dirname, '../src/lib/pluggy-client.ts');
const compiled = ts.transpileModule(fs.readFileSync(entry, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;
const exported = {};
vm.runInNewContext(compiled, {
  exports: exported,
  require(name) {
    assert.equal(name, '@/lib/i18n');
    return { t: (key, values = {}) => key.replace(/\{(\w+)\}/g, (_, name) => values[name]) };
  },
  URL, URLSearchParams, AbortController, setTimeout, clearTimeout,
  async fetch(url, init) {
    requests.push({ url, ...init, body: JSON.parse(init.body) });
    const isAuth = url.endsWith('/auth');
    return {
      ok: isAuth || !failToken,
      status: 400,
      text: async () => JSON.stringify(isAuth ? { apiKey: 'test-key' }
        : failToken ? { message: 'Invalid OAuth redirect URI' } : { accessToken: 'test-token' }),
    };
  },
}, { filename: entry });

async function main() {
  const client = exported.createPluggyClient('test-client', 'test-secret');
  const nativeCallback = 'cymba://settings';
  assert.equal(await client.connectToken(null, nativeCallback), 'test-token');
  const created = requests.at(-1);
  assert.equal(created.url, 'https://api.pluggy.ai/connect_token');
  assert.equal(created.headers['X-API-KEY'], 'test-key');
  assert.equal(JSON.stringify(created.body), JSON.stringify({ options: { oauthRedirectUri: nativeCallback } }));

  const itemId = 'ddc6e285-72ed-4150-972e-126e5a452ab2';
  await client.connectToken(itemId, nativeCallback);
  assert.equal(requests.at(-1).body.itemId, itemId);
  assert.equal(requests.at(-1).body.options.oauthRedirectUri, nativeCallback);
  assert.equal(requests.filter((request) => request.url.endsWith('/auth')).length, 1);

  const goCallback = 'exp://192.168.1.10:8081/--/settings';
  await client.connectToken(null, goCallback);
  assert.equal(requests.at(-1).body.options.oauthRedirectUri, goCallback);
  const count = requests.length;
  for (const host of ['localhost', '127.0.0.1', '[::1]']) {
    await assert.rejects(client.connectToken(null, `exp://${host}:8081/--/settings`), /--lan/);
  }
  assert.equal(requests.length, count, 'Reject unusable callbacks before making requests');
  failToken = true;
  await assert.rejects(client.connectToken(null, nativeCallback), /Invalid OAuth redirect URI/);
  console.log('Pluggy checks passed: create/reconnect redirects, Expo Go LAN links, key reuse and token errors.');
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
