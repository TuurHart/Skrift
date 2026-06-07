'use strict';

const { execSync } = require('child_process');
const path = require('path');

// Ad-hoc sign the .app so Gatekeeper shows "unidentified developer" instead of "damaged"
// when the DMG is transferred to another Mac via AirDrop / USB.
module.exports = async function afterSign({ appOutDir, packager }) {
  const appName = packager.appInfo.productName;
  const appPath = path.join(appOutDir, `${appName}.app`);
  console.log(`Ad-hoc signing: ${appPath}`);
  execSync(`codesign --force --deep --sign - "${appPath}"`, { stdio: 'inherit' });
};
