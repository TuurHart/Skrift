import { useState, useEffect } from 'react'
import QRCode from 'qrcode'

export function MobileTab() {
  const [localIP, setLocalIP] = useState<string>('...')
  const [hostname, setHostname] = useState<string>('Mac')
  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null)
  const port = 8000

  useEffect(() => {
    const api = (window as any).electronAPI
    if (api?.getLocalIP) {
      api.getLocalIP().then((ip: string) => setLocalIP(ip))
    }
    if (api?.getHostname) {
      api.getHostname().then((name: string) => setHostname(name))
    }
  }, [])

  useEffect(() => {
    if (localIP === '...') return
    const pairingUrl = `skrift://${localIP}:${port}/${encodeURIComponent(hostname)}`
    QRCode.toDataURL(pairingUrl, {
      width: 240,
      margin: 2,
      color: { dark: '#ffffffee', light: '#00000000' },
    }).then(setQrDataUrl).catch(() => {})
  }, [localIP, hostname])

  const pairingUrl = `skrift://${localIP}:${port}/${encodeURIComponent(hostname)}`

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-[10px] font-semibold uppercase tracking-[0.06em] text-text-muted mb-3">
          Mobile pairing
        </h3>
        <p className="text-[12px] text-text-secondary mb-4">
          Scan this QR code with the Skrift mobile app to pair your iPhone.
          Go to Settings → Mac Connection → Scan QR Code on the phone.
        </p>
      </div>

      <div className="flex flex-col items-center gap-4 py-4">
        {qrDataUrl ? (
          <img src={qrDataUrl} alt="Pairing QR code" className="w-[240px] h-[240px]" />
        ) : (
          <div className="w-[240px] h-[240px] bg-white/5 rounded-xl flex items-center justify-center">
            <span className="text-text-muted text-[13px]">Generating QR...</span>
          </div>
        )}

        <div className="text-center">
          <div className="text-[11px] text-text-muted mb-1">Pairing URL</div>
          <code className="text-[12px] text-accent/80 bg-white/5 px-3 py-1.5 rounded-md select-all">
            {pairingUrl}
          </code>
        </div>
      </div>

      <div className="space-y-2">
        <h3 className="text-[10px] font-semibold uppercase tracking-[0.06em] text-text-muted mb-2">
          Connection info
        </h3>
        <div className="bg-white/[0.03] rounded-lg border border-border/[0.07] divide-y divide-border/[0.07]">
          <div className="flex justify-between px-4 py-2.5">
            <span className="text-[13px] text-text-secondary">Local IP</span>
            <span className="text-[13px] text-text-primary font-mono">{localIP}</span>
          </div>
          <div className="flex justify-between px-4 py-2.5">
            <span className="text-[13px] text-text-secondary">Port</span>
            <span className="text-[13px] text-text-primary font-mono">{port}</span>
          </div>
          <div className="flex justify-between px-4 py-2.5">
            <span className="text-[13px] text-text-secondary">Device name</span>
            <span className="text-[13px] text-text-primary">{hostname}</span>
          </div>
        </div>
      </div>

      <div className="bg-accent/5 border border-accent/10 rounded-lg px-4 py-3">
        <p className="text-[12px] text-text-secondary">
          <span className="font-medium text-accent/80">Tip:</span> Both devices must be on the same WiFi network.
          The phone connects directly to this Mac — no cloud, no accounts needed.
        </p>
      </div>
    </div>
  )
}
