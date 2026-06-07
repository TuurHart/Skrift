import { useState, useRef, useCallback } from 'react'

interface SSEState {
  streaming: boolean
  text: string
  error: string | null
  status: string | null
}

export function useSSE() {
  const [state, setState] = useState<SSEState>({ streaming: false, text: '', error: null, status: null })
  const cleanupRef = useRef<(() => void) | null>(null)

  const stop = useCallback(() => {
    cleanupRef.current?.()
    cleanupRef.current = null
    setState(s => ({ ...s, streaming: false, status: null }))
  }, [])

  const start = useCallback((
    startStream: (callbacks: { onToken: (t: string) => void; onDone: (full: string) => void; onError: (msg: string) => void; onStatus?: (msg: string) => void }) => () => void,
    onComplete?: (fullText: string) => void,
  ) => {
    stop()
    setState({ streaming: true, text: '', error: null, status: null })

    const cleanup = startStream({
      onToken: (t) => setState(s => ({ ...s, text: s.text + t })),
      onDone: (full) => {
        setState({ streaming: false, text: full, error: null, status: null })
        onComplete?.(full)
      },
      onError: (msg) => setState({ streaming: false, text: '', error: msg, status: null }),
      onStatus: (msg) => setState(s => ({ ...s, status: msg })),
    })

    cleanupRef.current = cleanup
  }, [stop])

  const reset = useCallback(() => {
    stop()
    setState({ streaming: false, text: '', error: null, status: null })
  }, [stop])

  return { ...state, start, stop, reset }
}
