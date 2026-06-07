/** @type {import('@bacons/apple-targets/app.plugin').Config} */
module.exports = {
  type: "widget",
  displayName: "Skrift Record",
  colors: {
    // Accent purple from the Skrift design system
    $accent: { color: "#7c6bf5", darkColor: "#7c6bf5" },
    $widgetBackground: { color: "#0f1117", darkColor: "#0f1117" },
  },
  deploymentTarget: "16.0",
  // Append to main bundle ID: com.skrift.mobile.record-widget
  bundleIdentifier: ".record-widget",
};
