'use strict';
// Local, offline launcher for the tested Godot WebAssembly build.  This file
// is normally embedded into a single-file Windows Node SEA executable.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawn, exec } = require('node:child_process');
const { isSea, getAsset: seaGetAsset } = require('node:sea');

const ROOT = path.resolve(__dirname, '..');
const FILES = {
  'index.html': '.web/index.html',
  'index.js': '.web/index.js',
  'index.wasm': '.web/index.wasm',
  'index.pck': '.web/index.pck',
  'index.audio.worklet.js': '.web/index.audio.worklet.js',
  'index.audio.position.worklet.js': '.web/index.audio.position.worklet.js',
  'LICENSE': 'LICENSE',
  'CREDITS.md': 'CREDITS.md',
  'assets/icon.svg': 'assets/icon.svg',
  'assets/fonts/IBMPlexMono-OFL.txt': 'assets/fonts/IBMPlexMono-OFL.txt',
  'assets/fonts/Oswald-OFL.txt': 'assets/fonts/Oswald-OFL.txt',
  'licenses/Godot-MIT.txt': 'licenses/Godot-MIT.txt',
  'licenses/Godot-COPYRIGHT.txt': 'licenses/Godot-COPYRIGHT.txt',
  'licenses/Node-MIT.txt': 'licenses/Node-MIT.txt',
  'licenses/Preview-package-MIT.txt': 'licenses/Preview-package-MIT.txt',
};
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.svg': 'image/svg+xml',
  '.md': 'text/markdown; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
};
const PORT_START = 41737;
const MAX_PORT_TRIES = 20;
let exitTimer;

function getFile(name) {
  if (!Object.hasOwn(FILES, name)) return null;
  if (isSea()) return Buffer.from(seaGetAsset(name));
  return fs.readFileSync(path.join(ROOT, FILES[name]));
}

function isLoopback(address) {
  return address === '127.0.0.1' || address === '::1' || address === '::ffff:127.0.0.1';
}

const server = http.createServer((request, response) => {
  if (!isLoopback(request.socket.remoteAddress)) {
    response.writeHead(403).end();
    return;
  }
  const securityHeaders = {
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'require-corp',
    'Cross-Origin-Resource-Policy': 'same-origin',
    'X-Content-Type-Options': 'nosniff',
    'Cache-Control': 'no-store',
  };
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
  } catch {
    response.writeHead(400, securityHeaders).end();
    return;
  }

  if (pathname === '/__quit' && request.method === 'POST') {
    response.writeHead(204, securityHeaders).end();
    clearTimeout(exitTimer);
    exitTimer = setTimeout(() => server.close(() => process.exit(0)), 4500);
    exitTimer.unref();
    return;
  }
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    response.writeHead(405, { ...securityHeaders, Allow: 'GET, HEAD' }).end();
    return;
  }
  clearTimeout(exitTimer);
  if (pathname === '/__health') {
    const body = Buffer.from(JSON.stringify({ game: 'Нижний уровень', engine: 'Godot 4.6 WebAssembly', offline: true }));
    response.writeHead(200, { ...securityHeaders, 'Content-Type': 'application/json', 'Content-Length': body.length });
    response.end(request.method === 'HEAD' ? undefined : body);
    return;
  }

  let name = pathname === '/' ? 'index.html' : pathname.slice(1);
  if (name === 'favicon.ico') name = 'assets/icon.svg';
  const body = getFile(name);
  if (!body) {
    response.writeHead(404, { ...securityHeaders, 'Content-Type': 'text/plain; charset=utf-8' }).end('Not found');
    return;
  }
  response.writeHead(200, {
    ...securityHeaders,
    'Content-Type': MIME[path.extname(name)] || 'application/octet-stream',
    'Content-Length': body.length,
  });
  response.end(request.method === 'HEAD' ? undefined : body);
});

function showInBrowser(url) {
  if (process.platform !== 'win32' || !isSea()) {
    console.log(`Offline Godot game: ${url}`);
    return;
  }
  // Delegate to Windows' registered web browser; the game files themselves are
  // all inside this executable and are served only on the loopback interface.
  exec(`start "" "${url}"`, { windowsHide: true }, (error) => {
    if (error) {
      spawn('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', 'Start-Process', url], {
        detached: true, windowsHide: true, stdio: 'ignore',
      }).unref();
    }
  });
}

function listenOn(port, attemptsLeft) {
  const onError = (error) => {
    server.off('listening', onListening);
    if (error.code === 'EADDRINUSE' && attemptsLeft > 0) {
      listenOn(port + 1, attemptsLeft - 1);
    } else {
      console.error(`Could not start the local game server: ${error.message}`);
      process.exitCode = 1;
    }
  };
  const onListening = () => {
    server.off('error', onError);
    const address = server.address();
    const url = `http://127.0.0.1:${address.port}/`;
    showInBrowser(url);
  };
  server.once('error', onError);
  server.once('listening', onListening);
  server.listen(port, '127.0.0.1');
}

listenOn(PORT_START, MAX_PORT_TRIES);
