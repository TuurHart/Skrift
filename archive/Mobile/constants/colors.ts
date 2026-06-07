/**
 * Color tokens matching the Skrift desktop app.
 * Dark theme is default.
 */
export const colors = {
  dark: {
    bg: '#0f1117',
    surface: '#181a23',
    surfaceHover: '#1e2130',
    border: 'rgba(255, 255, 255, 0.07)',
    textPrimary: '#e4e4e7',
    textSecondary: '#8b8b97',
    textMuted: '#55556a',
    accent: '#7c6bf5',
    checkGreen: '#34d399',
    destructive: '#ef4444',
    stepEnhance: '#f59e0b',
  },
  light: {
    bg: '#f5f5f7',
    surface: '#ffffff',
    surfaceHover: '#f0f0f3',
    border: 'rgba(0, 0, 0, 0.07)',
    textPrimary: '#1a1a2e',
    textSecondary: '#5c5c6f',
    textMuted: '#9d9db0',
    accent: '#6c5ce7',
    checkGreen: '#22c55e',
    destructive: '#ef4444',
    stepEnhance: '#d97706',
  },
} as const;

/** Shortcut — default to dark theme */
export const theme = colors.dark;
