/** Format a backend "HH:MM:SS" duration string, dropping leading zero hours
 *  (e.g. "00:02:14" → "2:14", "01:05:09" → "1:05:09"). */
export function formatDuration(raw: string | undefined): string {
  if (!raw) return ''
  const parts = raw.split(':').map(Number)
  if (parts.length === 3) {
    const [h, m, s] = parts
    return h > 0
      ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
      : `${m}:${String(s).padStart(2, '0')}`
  }
  return raw
}
