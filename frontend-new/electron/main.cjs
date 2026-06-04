'use strict';

const { app, BrowserWindow, ipcMain, dialog, shell, Menu, protocol, nativeTheme, net } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { spawn } = require('child_process');

// ── Config ──────────────────────────────────────────────────

const isDev = process.env.NODE_ENV === 'development';
const DEV_URL = 'http://localhost:5173';
const BACKEND_URL = 'http://localhost:8000/health';

let mainWindow = null;
let isQuitting = false;
let backendProc = null;

// ── Backend helpers ─────────────────────────────────────────

async function isBackendRunning() {
  try {
    const res = await net.fetch(BACKEND_URL, { signal: AbortSignal.timeout(2000) });
    return res.ok;
  } catch { return false; }
}

function spawnBackend() {
  // 1. Bundled inside .app (extraResources → Contents/Resources/backend/)
  const bundledScript = path.join(process.resourcesPath, 'backend', 'start_backend.sh');
  // 2. Dev mode: relative to electron/ dir
  const relScript = path.join(__dirname, '..', '..', 'backend', 'start_backend.sh');
  const script = fs.existsSync(bundledScript) ? bundledScript : relScript;
  backendProc = spawn('bash', ['-l', script, 'start'], { stdio: 'ignore', detached: true });
  backendProc.on('error', (err) => {
    console.error('Failed to spawn backend:', err);
    setLoadingStatus('Backend failed to start — check logs');
  });
  backendProc.unref();
}

async function waitForBackend(timeoutMs = 60000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await isBackendRunning()) return true;
    await new Promise(r => setTimeout(r, 600));
  }
  return false;
}

function setLoadingStatus(msg) {
  mainWindow?.webContents.executeJavaScript(
    `document.getElementById('status') && (document.getElementById('status').textContent = ${JSON.stringify(msg)})`
  ).catch(() => {});
}

// ── Window ──────────────────────────────────────────────────

async function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 1100,
    minHeight: 700,
    show: false,
    // Native macOS chrome: inset traffic lights over the content, with a
    // draggable titlebar region (the sidebar header sets WebkitAppRegion: drag).
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 13, y: 18 },
    backgroundColor: '#0f1117',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,  // Required for File.path on drag-drop (both dev and prod)
      preload: path.join(__dirname, 'preload.cjs'),
      webSecurity: !isDev,
      devTools: true,
    },
  });

  // Show loading screen first
  await mainWindow.loadFile(path.join(__dirname, 'loading.html'));

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
    if (isDev) mainWindow.webContents.openDevTools();
  });

  mainWindow.on('close', (e) => {
    if (process.platform === 'darwin' && !isQuitting) {
      e.preventDefault();
      mainWindow.hide();
    }
  });

  mainWindow.on('closed', () => { mainWindow = null; });

  // Forward find-in-page results to renderer for match count display
  mainWindow.webContents.on('found-in-page', (_event, result) => {
    mainWindow?.webContents.send('found-in-page-result', {
      activeMatchOrdinal: result.activeMatchOrdinal,
      matches: result.matches,
    });
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  // Right-click context menu with edit roles + spellcheck
  mainWindow.webContents.on('context-menu', (_e, params) => {
    const items = [];
    if (params.misspelledWord && params.dictionarySuggestions?.length) {
      for (const s of params.dictionarySuggestions) {
        items.push({ label: s, click: () => mainWindow?.webContents.replaceMisspelling(s) });
      }
      items.push({ type: 'separator' });
    }
    if (params.isEditable) {
      items.push({ role: 'undo' }, { role: 'redo' }, { type: 'separator' },
        { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { type: 'separator' },
        { role: 'selectAll' });
    } else {
      items.push({ role: 'copy' }, { type: 'separator' }, { role: 'selectAll' });
    }
    if (items.length) Menu.buildFromTemplate(items).popup({ window: mainWindow });
  });

  return mainWindow;
}

function createMenu() {
  const template = [
    ...(process.platform === 'darwin' ? [{
      label: app.getName(),
      submenu: [
        { role: 'about' }, { type: 'separator' },
        { role: 'services' }, { type: 'separator' },
        { role: 'hide' }, { role: 'hideOthers' }, { role: 'unhide' }, { type: 'separator' },
        { role: 'quit' },
      ],
    }] : []),
    {
      label: 'File',
      submenu: [
        {
          label: 'Open Settings',
          accelerator: 'CmdOrCtrl+,',
          click: () => mainWindow?.webContents.send('menu-preferences'),
        },
        { type: 'separator' },
        process.platform === 'darwin' ? { role: 'close' } : { role: 'quit' },
      ],
    },
    { label: 'Edit', submenu: [
      { role: 'undo' }, { role: 'redo' }, { type: 'separator' },
      { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' },
      { type: 'separator' },
      {
        label: 'Find',
        accelerator: 'CmdOrCtrl+F',
        click: () => mainWindow?.webContents.send('toggle-find'),
      },
      {
        label: 'Find Next',
        accelerator: 'CmdOrCtrl+G',
        click: () => mainWindow?.webContents.send('find-next'),
      },
      {
        label: 'Close Find',
        accelerator: 'Escape',
        click: () => mainWindow?.webContents.send('close-find'),
        visible: false,
      },
    ]},
    { label: 'View', submenu: [
      { role: 'reload' }, { role: 'forceReload' }, { role: 'toggleDevTools' },
      { type: 'separator' }, { role: 'togglefullscreen' },
    ]},
    { label: 'Window', submenu: [
      { role: 'minimize' },
      ...(process.platform === 'darwin' ? [{ role: 'zoom' }, { type: 'separator' }, { role: 'front' }] : [{ role: 'close' }]),
    ]},
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

// ── Find in page ───────────────────────────────────────────

ipcMain.handle('find:findInPage', (_event, text, options) => {
  if (!mainWindow || !text) return null;
  mainWindow.webContents.findInPage(text, options || {});
  return null;
});

ipcMain.handle('find:stopFindInPage', (_event, action) => {
  if (!mainWindow) return;
  mainWindow.webContents.stopFindInPage(action || 'clearSelection');
});

// ── App lifecycle ───────────────────────────────────────────

app.whenReady().then(async () => {
  // Allow file:// protocol for audio playback
  protocol.registerFileProtocol('file', (req, cb) => cb(decodeURI(req.url.replace('file:///', '/'))));

  await createWindow();
  createMenu();

  const alreadyUp = await isBackendRunning();
  if (!alreadyUp) {
    setLoadingStatus('Starting backend…');
    spawnBackend();
  } else {
    setLoadingStatus('Connecting…');
  }

  const ready = await waitForBackend(60000);
  if (!ready) {
    dialog.showErrorBox('Backend failed to start',
      'The backend did not start within 60 seconds.\n\n' +
      'If this is a fresh install, make sure you ran setup.sh first.\n' +
      'Check ~/Library/Application Support/Skrift/backend.log for details.');
    app.quit();
    return;
  }

  setLoadingStatus('Ready');
  await new Promise(r => setTimeout(r, 250));

  if (isDev) {
    await mainWindow?.loadURL(DEV_URL);
  } else {
    await mainWindow?.loadFile(path.join(__dirname, '..', 'renderer-dist', 'index.html'));
  }

  app.on('activate', async () => {
    if (BrowserWindow.getAllWindows().length === 0) await createWindow();
    else mainWindow?.show();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('before-quit', () => {
  isQuitting = true;
  // Ask backend to stop gracefully — use same fallback path logic as spawnBackend()
  const relScript = path.join(__dirname, '..', '..', 'backend', 'start_backend.sh');
  const absScript = path.join(os.homedir(), 'Hackerman', 'Skrift', 'backend', 'start_backend.sh');
  const script = fs.existsSync(relScript) ? relScript : absScript;
  try {
    spawn('bash', ['-l', script, 'stop'], { stdio: 'ignore', detached: true }).unref();
  } catch { /* ignore */ }
});

// ── IPC handlers ────────────────────────────────────────────

ipcMain.handle('dialog:openFiles', async (_e, options = {}) => {
  if (!mainWindow) return null;
  const exts = (options.accept ?? ['m4a', 'wav', 'mp3', 'md'])
    .map((/** @type {string} */ s) => s.replace(/^\./, ''));
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openFile', options.multiple !== false ? 'multiSelections' : undefined].filter(Boolean),
    filters: [{ name: 'Audio & Notes', extensions: exts }, { name: 'All Files', extensions: ['*'] }],
  });
  return result.canceled ? null : result.filePaths;
});

ipcMain.handle('dialog:openFolder', async () => {
  if (!mainWindow) return null;
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openDirectory'],
  });
  return result.canceled ? null : result.filePaths[0];
});

// Classify a list of paths into files and folders
ipcMain.handle('paths:classify', (_e, paths) => {
  const fs = require('fs');
  const files = [];
  const folders = [];
  for (const p of (paths || [])) {
    try {
      if (fs.statSync(p).isDirectory()) folders.push(p);
      else files.push(p);
    } catch { /* skip unreadable */ }
  }
  return { files, folders };
});

// Combined picker: returns { files: string[], folders: string[] }
ipcMain.handle('dialog:openUpload', async () => {
  if (!mainWindow) return null;
  const fs = require('fs');
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openFile', 'openDirectory', 'multiSelections'],
    filters: [{ name: 'Audio & Notes', extensions: ['m4a', 'wav', 'mp3', 'md'] }, { name: 'All Files', extensions: ['*'] }],
  });
  if (result.canceled) return null;
  const files = [];
  const folders = [];
  for (const p of result.filePaths) {
    try {
      if (fs.statSync(p).isDirectory()) folders.push(p);
      else files.push(p);
    } catch { files.push(p); }
  }
  return { files, folders };
});

ipcMain.handle('system:getInfo', () => ({
  appVersion: app.getVersion(),
  platform: process.platform,
  electronVersion: process.versions.electron,
  nodeVersion: process.versions.node,
}));

ipcMain.handle('theme:getSystem', () =>
  nativeTheme.shouldUseDarkColors ? 'dark' : 'light'
);

ipcMain.handle('system:getLocalIP', () => {
  const os = require('os');
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name] || []) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return '127.0.0.1';
});

ipcMain.handle('system:getHostname', () => {
  const os = require('os');
  return os.hostname();
});

// Forward menu-preferences IPC event (triggered from menu)
// The renderer listens via window.addEventListener or a hook
