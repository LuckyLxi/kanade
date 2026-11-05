import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';

// MuMu 15 (Android 15, root) 里的官方 QQ 音乐经 Fiddler 抓包。
// 模拟器访问 10.0.2.2 会落到宿主机 127.0.0.1，Fiddler 无需允许远程连接。
const device = '127.0.0.1:16384';
const mumuManager = 'D:/MuMuPlayer/nx_main/MuMuManager.exe';
const packageName = 'com.tencent.qqmusic';
const proxy = '10.0.2.2:8888';
const remoteDir = '/data/local/tmp/kanade-capture';

const mode = process.argv[2] ?? '--check';
if (!['--check', '--prepare', '--restore'].includes(mode)) throw new Error('Use --check, --prepare or --restore.');

function adb(...args) {
  return execFileSync('adb', ['-s', device, ...args], { encoding: 'utf8' }).trim();
}

function su(script) {
  const local = path.join(os.tmpdir(), 'kanade-capture.sh');
  fs.writeFileSync(local, `set -e\n${script}\n`);
  adb('shell', `mkdir -p ${remoteDir}`);
  adb('push', local, `${remoteDir}/run.sh`);
  return adb('shell', `su -c 'sh ${remoteDir}/run.sh'`);
}

const info = JSON.parse(execFileSync(mumuManager, ['info', '-v', '0'], { encoding: 'utf8' }));
if (!info.is_android_started) throw new Error('MuMu device 0 is not started; launch it first.');
execFileSync('adb', ['connect', device], { encoding: 'utf8' });

if (mode === '--restore') {
  console.log(su([
    'settings put global http_proxy :0',
    'iptables -D OUTPUT -p udp --dport 443 -j REJECT 2>/dev/null || true',
    'ip6tables -D OUTPUT -p udp --dport 443 -j REJECT 2>/dev/null || true',
    `am force-stop ${packageName}`,
    'echo restored',
  ].join('\n')));
  console.log('Proxy and UDP 443 block removed. The injected CA disappears on the next emulator restart.');
} else {
  if (adb('shell', "su -c 'id -u'") !== '0') {
    throw new Error('Root unavailable. Run: mumu-cli setting -v 0 -k root_permission -val true, then restart MuMu.');
  }
  if (!adb('shell', `pm list packages ${packageName}`).split(/\s+/).includes(`package:${packageName}`)) throw new Error('Official QQ Music is not installed in MuMu.');
  await new Promise((resolve, reject) => {
    const socket = net.connect({ host: '127.0.0.1', port: 8888 });
    socket.setTimeout(3000);
    socket.once('connect', () => { socket.destroy(); resolve(); });
    socket.once('error', reject);
    socket.once('timeout', () => { socket.destroy(); reject(new Error('Fiddler listener timed out.')); });
  });
  const der = Buffer.from(execFileSync('powershell', ['-NoProfile', '-Command',
    "[Convert]::ToBase64String((Get-ChildItem Cert:/CurrentUser/Root | Where-Object Subject -match 'DO_NOT_TRUST_FiddlerRoot' | Select-Object -First 1).RawData)",
  ], { encoding: 'utf8' }).trim(), 'base64');
  if (!der.length) throw new Error('Fiddler root certificate not found; enable HTTPS decryption in Fiddler.');
  const hash = execFileSync('openssl', ['x509', '-inform', 'DER', '-noout', '-subject_hash_old'], { input: der, encoding: 'utf8' }).trim();
  const pem = execFileSync('openssl', ['x509', '-inform', 'DER'], { input: der, encoding: 'utf8' });
  console.log(`Device ${device}, Android ${adb('shell', 'getprop ro.build.version.release')}, CA ${hash}.0, proxy ${proxy}.`);
  if (mode === '--check') {
    console.log('Read-only preparation check passed; emulator has not been changed.');
  } else {
    const local = path.join(os.tmpdir(), `${hash}.0`);
    fs.writeFileSync(local, pem);
    adb('shell', `mkdir -p ${remoteDir}`);
    adb('push', local, `${remoteDir}/${hash}.0`);
    // Android 14+ 从 conscrypt APEX 读系统 CA：在 tmpfs 里拼好证书目录，再 bind 进 zygote 的挂载命名空间。
    console.log(su([
      'CA=/system/etc/security/cacerts',
      'APEX=/apex/com.android.conscrypt/cacerts',
      'if ! grep -q " $CA tmpfs " /proc/mounts; then',
      `  mkdir -p -m 700 ${remoteDir}/ca`,
      `  cp $APEX/* ${remoteDir}/ca/`,
      '  mount -t tmpfs tmpfs $CA',
      `  mv ${remoteDir}/ca/* $CA/`,
      'fi',
      `cp ${remoteDir}/${hash}.0 $CA/`,
      'chown root:root $CA/*',
      'chmod 644 $CA/*',
      'chcon u:object_r:system_file:s0 $CA/*',
      'for Z in $(pidof zygote zygote64); do',
      '  nsenter --mount=/proc/$Z/ns/mnt -- ls $APEX/' + hash + '.0 >/dev/null 2>&1 || nsenter --mount=/proc/$Z/ns/mnt -- mount --bind $CA $APEX',
      'done',
      // Fiddler 不处理 QUIC，拒绝 UDP 443 让 App 回落到经代理的 HTTPS。
      'iptables -C OUTPUT -p udp --dport 443 -j REJECT 2>/dev/null || iptables -I OUTPUT -p udp --dport 443 -j REJECT',
      'ip6tables -C OUTPUT -p udp --dport 443 -j REJECT 2>/dev/null || ip6tables -I OUTPUT -p udp --dport 443 -j REJECT',
      `settings put global http_proxy ${proxy}`,
      `am force-stop ${packageName}`,
      'echo prepared',
    ].join('\n')));
    console.log('Open QQ Music in MuMu and use song recognition; sessions appear in Fiddler. Run --restore when done.');
  }
}
