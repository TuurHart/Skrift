/** @type {import('tailwindcss').Config} */
export default {
  darkMode: ['class'],
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // App design tokens — mapped to CSS variables with RGB space-separated values
        // Usage: bg-surface, bg-accent/15, border-border/[0.07], text-text-muted, etc.
        bg: 'rgb(var(--color-bg) / <alpha-value>)',
        surface: 'rgb(var(--color-surface) / <alpha-value>)',
        'surface-hover': 'rgb(var(--color-surface-hover) / <alpha-value>)',
        'text-primary': 'rgb(var(--color-text-primary) / <alpha-value>)',
        'text-secondary': 'rgb(var(--color-text-secondary) / <alpha-value>)',
        'text-muted': 'rgb(var(--color-text-muted) / <alpha-value>)',
        accent: 'rgb(var(--color-accent) / <alpha-value>)',
        'check-green': 'rgb(var(--color-check-green) / <alpha-value>)',
        destructive: 'rgb(var(--color-destructive) / <alpha-value>)',
        // Pipeline step dot colors
        'step-transcribe': 'rgb(var(--color-step-transcribe) / <alpha-value>)',
        'step-sanitise': 'rgb(var(--color-step-sanitise) / <alpha-value>)',
        'step-enhance': 'rgb(var(--color-step-enhance) / <alpha-value>)',
        'step-export': 'rgb(var(--color-step-export) / <alpha-value>)',
        // Border token (used as border-border/[0.07] etc.)
        border: 'rgb(var(--color-border) / <alpha-value>)',
      },
      fontFamily: {
        sans: [
          '-apple-system',
          'BlinkMacSystemFont',
          '"Segoe UI"',
          'Helvetica Neue',
          'Arial',
          'sans-serif',
        ],
      },
    },
  },
  plugins: [require('tailwindcss-animate')],
}
