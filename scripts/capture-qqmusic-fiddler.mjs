import fs from 'node:fs';
import net from 'node:net';

const configPath = `${process.env.APPDATA}/com.follow/clash/config.yaml`;
const original = fs.readFileSync(configPath, 'utf8');
const secretValue = original.match(/^secret:[ \t]*(.*)$/m)?.[1]?.trim() ?? '';
const secret = secretValue.startsWith('"')
  ? JSON.parse(secretValue)
  : secretValue.startsWith("'")
    ? secretValue.slice(1, -1).replace(/''/g, "'")
    : secretValue;
const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${secret}` };
const proxyName = 'Kanade-QQMusic-Fiddler';
const recommendations = process.argv.includes('--recommendations');
const player = process.argv.includes('--player');
const expandedScope = recommendations || player;
// 当前 PC 客户端既有 qmbrowser 网页请求，也有主进程到该 API IP 的 HTTP 直连。
const rule = expandedScope
  ? `AND,((OR,((PROCESS-NAME,QQMusic.exe),(PROCESS-NAME,QQMusicExternal.exe),(PROCESS-NAME,qmbrowser.exe))),(OR,((DOMAIN-SUFFIX,y.qq.com),(AND,((IP-CIDR,157.148.63.240/32,no-resolve),(DST-PORT,80)))))),${proxyName}`
  : `AND,((PROCESS-NAME,QQMusic.exe),(DOMAIN,u6.y.qq.com)),${proxyName}`;
const captureSeconds = player ? 300 : recommendations ? 180 : 45;

function matchesTarget(metadata) {
  const host = metadata?.host?.toLowerCase() ?? '';
  const processMatches = metadata?.process === 'QQMusic.exe'
    || (expandedScope && ['QQMusicExternal.exe', 'qmbrowser.exe'].includes(metadata?.process));
  return processMatches && (expandedScope
    ? host === 'y.qq.com' || host.endsWith('.y.qq.com')
      || (metadata?.destinationIP === '157.148.63.240' && String(metadata?.destinationPort) === '80')
    : host === 'u6.y.qq.com');
}

async function api(path, method = 'GET', body) {
  const response = await fetch(`http://127.0.0.1:9090${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`Controller ${method} ${path}: HTTP ${response.status}`);
  return response.status === 204 ? undefined : response.json();
}

function prependList(yaml, key, lines) {
  const header = new RegExp(`^${key}:[ \\t]*\\r?\\n(?=[ \\t]*-)`, 'm');
  const match = header.exec(yaml);
  if (!match) throw new Error(`Unsupported ${key} layout; configuration was not changed.`);
  const offset = match.index + match[0].length;
  const indent = yaml.slice(offset).match(/^[ \t]*/)[0];
  return yaml.slice(0, offset) + lines.map(line => indent + line).join('\n') + '\n' + yaml.slice(offset);
}

const temporary = prependList(prependList(original, 'proxies', [
  `- name: ${proxyName}`,
  '  type: http',
  '  server: 127.0.0.1',
  '  port: 8888',
]), 'rules', [`- '${rule}'`]);

const mode = process.argv[2] ?? '--check';
if (!['--check', '--capture', '--restore'].includes(mode)) throw new Error('Use --check, --capture or --restore.');
if (process.argv.slice(3).some(arg => !['--recommendations', '--player'].includes(arg))) throw new Error('Unknown option. Use --capture --recommendations or --capture --player.');
const current = await api('/configs');
if (mode === '--restore') {
  await api('/configs?force=true', 'PUT', { payload: original });
  console.log('Restored configuration from the unchanged FlClash config file.');
} else {
  if (current.mode !== 'rule' || current['find-process-mode'] !== 'always') {
    throw new Error('Expected rule mode with process detection enabled; configuration was not changed.');
  }
  await new Promise((resolve, reject) => {
    const socket = net.connect({ host: '127.0.0.1', port: 8888 });
    socket.setTimeout(3000);
    socket.once('connect', () => { socket.destroy(); resolve(); });
    socket.once('error', reject);
    socket.once('timeout', () => { socket.destroy(); reject(new Error('Fiddler listener timed out.')); });
  });
  console.log(`Target rule: ${rule}`);
  console.log('Target proxy: HTTP 127.0.0.1:8888. Original configuration file stays unchanged.');
  if (mode === '--check') {
    console.log('Read-only preparation check passed; routing has not been changed.');
  } else {
    const { proxies } = await api('/proxies');
    const selections = Object.entries(proxies).filter(([, p]) => p.type === 'Selector' && p.now);
    async function restoreSelections() {
      for (const [name, proxy] of selections) {
        await api(`/proxies/${encodeURIComponent(name)}`, 'PUT', { name: proxy.now });
      }
    }
    let applied = false;
    let interrupted = false;
    const onInterrupt = () => { interrupted = true; };
    process.once('SIGINT', onInterrupt);
    try {
      applied = true;
      await api('/configs?force=true', 'PUT', { payload: temporary });
      await restoreSelections();
      const { rules } = await api('/rules');
      if (rules[0]?.proxy !== proxyName) throw new Error('Temporary routing rule could not be verified.');
      const { connections } = await api('/connections');
      for (const connection of connections) {
        if (matchesTarget(connection.metadata)) {
          await api(`/connections/${encodeURIComponent(connection.id)}`, 'DELETE');
        }
      }
      console.log(player
        ? `CAPTURING PLAYER ACTIONS: open singer, comments and album; toggle the song heart and restore it; add to a test playlist and remove it. Temporary rule lasts ${captureSeconds} seconds.`
        : recommendations
          ? `CAPTURING RECOMMENDATIONS: reopen Home, open Daily 30 and personalized recommendations, then scroll the page. Temporary rule lasts ${captureSeconds} seconds.`
          : 'CAPTURING: search a NEW keyword in official QQMusic now. Temporary rule lasts 45 seconds.');
      console.log(`Capture started: ${new Date().toISOString()}`);
      const end = Date.now() + captureSeconds * 1000;
      const seen = new Set();
      while (!interrupted && Date.now() < end) {
        const { connections } = await api('/connections');
        for (const c of connections) {
          if (matchesTarget(c.metadata) && !seen.has(c.id)) {
            seen.add(c.id);
            console.log(JSON.stringify({ host: c.metadata.host, process: c.metadata.process, chains: c.chains }));
          }
        }
        await new Promise(resolve => setTimeout(resolve, 500));
      }
    } finally {
      if (applied) {
        await api('/configs?force=true', 'PUT', { payload: original });
        await restoreSelections();
        console.log('Original routing and proxy selections restored.');
      }
      process.removeListener('SIGINT', onInterrupt);
    }
  }
}
