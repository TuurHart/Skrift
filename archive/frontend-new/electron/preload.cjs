'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  // File dialog
  openFileDialog: (options) => ipcRenderer.invoke('dialog:openFiles', options),
  openFolderDialog: () => ipcRenderer.invoke('dialog:openFolder'),
  openUploadDialog: () => ipcRenderer.invoke('dialog:openUpload'),
  classifyPaths: (paths) => ipcRenderer.invoke('paths:classify', paths),

  // System info
  getSystemInfo: () => ipcRenderer.invoke('system:getInfo'),
  getLocalIP: () => ipcRenderer.invoke('system:getLocalIP'),
  getHostname: () => ipcRenderer.invoke('system:getHostname'),

  // System theme
  getSystemTheme: () => ipcRenderer.invoke('theme:getSystem'),

  // Menu event: settings opened via Cmd+,
  onMenuPreferences: (cb) => {
    const handler = () => cb();
    ipcRenderer.on('menu-preferences', handler);
    return () => ipcRenderer.removeListener('menu-preferences', handler);
  },

  // Find in page
  onToggleFind: (cb) => {
    const handler = () => cb();
    ipcRenderer.on('toggle-find', handler);
    return () => ipcRenderer.removeListener('toggle-find', handler);
  },
  onFindNext: (cb) => {
    const handler = () => cb();
    ipcRenderer.on('find-next', handler);
    return () => ipcRenderer.removeListener('find-next', handler);
  },
  onCloseFind: (cb) => {
    const handler = () => cb();
    ipcRenderer.on('close-find', handler);
    return () => ipcRenderer.removeListener('close-find', handler);
  },
  findInPage: (text, options) => ipcRenderer.invoke('find:findInPage', text, options),
  stopFindInPage: (action) => ipcRenderer.invoke('find:stopFindInPage', action),
  onFoundInPage: (cb) => {
    const handler = (_event, result) => cb(result);
    ipcRenderer.on('found-in-page-result', handler);
    return () => ipcRenderer.removeListener('found-in-page-result', handler);
  },
});
