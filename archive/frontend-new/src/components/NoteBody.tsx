import { useEffect, useRef, useCallback, useState } from 'react'
import type { PipelineFile } from '@/types/pipeline'
import { AddNameModal } from './AddNameModal'
import { API_BASE } from '@/api'
import { formatDuration } from '@/lib/format'

// Lightbox for click-to-enlarge images
function ImageLightbox({ src, alt, onClose }: { src: string; alt: string; onClose: () => void }) {
  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [onClose])

  return (
    <div
      onClick={onClose}
      style={{
        position: 'fixed', inset: 0, zIndex: 9999,
        background: 'rgba(0,0,0,0.85)', display: 'flex',
        alignItems: 'center', justifyContent: 'center', cursor: 'zoom-out',
      }}
    >
      <img src={src} alt={alt} style={{ maxWidth: '90vw', maxHeight: '90vh', borderRadius: 8 }} />
    </div>
  )
}

export function getBestText(file: PipelineFile): string | null {
  // Prefer the name-linked `sanitised` (what compile/export uses) so the desktop
  // body shows exactly what ships to Obsidian — [[links]] and all.
  return file.sanitised ?? file.enhanced_copyedit ?? file.transcript
}

function TranscribePlaceholder({ file, onTranscribe }: { file: PipelineFile; onTranscribe?: () => void }) {
  const isProcessing = file.steps.transcribe === 'processing'

  return (
    <div className="flex flex-col items-center py-16 text-text-muted">
      <div className="w-16 h-16 rounded-2xl bg-white/[0.05] flex items-center justify-center text-3xl mb-4 select-none">🎙</div>
      <p className="text-[15px] mb-1">{file.filename}</p>
      {file.audioMetadata?.duration && <p className="text-[12px] mb-5">{formatDuration(file.audioMetadata.duration)}</p>}
      <button
        onClick={onTranscribe}
        disabled={!onTranscribe || isProcessing}
        className="px-6 py-2.5 rounded-lg bg-accent text-white text-[14px] font-medium hover:bg-accent/90 transition-colors disabled:opacity-40 disabled:cursor-not-allowed flex items-center gap-2"
      >
        {isProcessing && (
          <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin inline-block" />
        )}
        {isProcessing ? 'Transcribing…' : 'Transcribe this memo'}
      </button>
    </div>
  )
}

interface NoteBodyProps {
  file: PipelineFile
  onTranscribe?: () => void
  onBodySave: (text: string, field: 'copyedit' | 'sanitised' | 'transcript') => void
}

export function NoteBody({ file, onTranscribe, onBodySave }: NoteBodyProps) {
  const isAppleNote = file.source_type === 'note'
  const transcribed = file.steps.transcribe === 'done'
  const divRef = useRef<HTMLDivElement>(null)
  const saveTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const lastFileId = useRef<string | null>(null)
  // Race guard: true from the first keystroke until the server echoes our save.
  // While dirty, an in-flight refetch must never overwrite the editor.
  const dirtyRef = useRef(false)
  const lastSentRef = useRef<string | null>(null)

  // Selection toolbar state
  const [toolbarPos, setToolbarPos] = useState<{ x: number; y: number } | null>(null)
  const [selectedWord, setSelectedWord] = useState<string | null>(null)
  const [showAddName, setShowAddName] = useState(false)
  // modalWord is saved at the moment "Add name" is clicked and stays stable
  // while the modal is open — it's never touched by the mousedown listener
  const [modalWord, setModalWord] = useState<string | null>(null)
  const toolbarRef = useRef<HTMLDivElement>(null)

  const [lightboxSrc, setLightboxSrc] = useState<{ src: string; alt: string } | null>(null)

  const bestText = getBestText(file)
  const hasImages = bestText
    ? /!\[\[.+?\.(jpg|jpeg|png)\]\]/i.test(bestText) || /\[\[img_\d{3}\]\]/.test(bestText) || /!\[[^\]]*\]\([^)]+?\.(jpg|jpeg|png|gif|webp)\)/i.test(bestText)
    : false

  // Convert image markers to img tags for rendering.
  // Handles two formats:
  //   ![[filename.jpg]] — post-export Obsidian embeds
  //   [[img_001]]       — pre-export timestamped photo markers (resolved via manifest)
  function textToHtml(text: string, fileId: string): string {
    // Escape HTML entities first
    let html = text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')

    // Convert ![[image.jpg]] to img tags (post-export format)
    html = html.replace(
      /!\[\[([^\]]+?\.(jpg|jpeg|png))\]\]/gi,
      (_match, fullMarker, _ext) => {
        const safeFilename = fullMarker.replace(/"/g, '&quot;')
        const src = `${API_BASE}/api/files/${fileId}/images/${encodeURIComponent(fullMarker)}`
        return `<img src="${src}" alt="${safeFilename}" data-marker="![[${safeFilename}]]" style="max-width:120px;border-radius:6px;margin:6px 0;display:inline-block;cursor:zoom-in;vertical-align:middle;" contenteditable="false" />`
      }
    )

    // Convert [[img_001]] to img tags (pre-export manifest-based markers)
    // Uses the /api/files/{id}/images/img_001 endpoint which resolves via manifest
    html = html.replace(
      /\[\[(img_\d{3})\]\]/g,
      (_match, marker) => {
        const src = `${API_BASE}/api/files/${fileId}/images/${marker}`
        return `<img src="${src}" alt="${marker}" data-marker="[[${marker}]]" style="max-width:120px;border-radius:6px;margin:6px 0;display:inline-block;cursor:zoom-in;vertical-align:middle;" contenteditable="false" />`
      }
    )

    // Convert standard markdown images (Apple Notes: ![alt](Attachments/foo.jpg))
    // to img tags. Serve the basename via the images endpoint (which also looks
    // in Attachments/); keep the original markdown in data-marker so edits round-trip.
    html = html.replace(
      /!\[[^\]]*\]\(([^)]+?\.(?:jpg|jpeg|png|gif|webp))\)/gi,
      (match, path) => {
        const base = (path.split('/').pop() || path)
        const src = `${API_BASE}/api/files/${fileId}/images/${encodeURIComponent(base)}`
        const marker = match.replace(/"/g, '&quot;')
        return `<img src="${src}" alt="${base}" data-marker="${marker}" style="max-width:120px;border-radius:6px;margin:6px 0;display:inline-block;cursor:zoom-in;vertical-align:middle;" contenteditable="false" />`
      }
    )

    // Convert newlines to <br>
    html = html.replace(/\n/g, '<br>')
    return html
  }

  // Sync content into the div when:
  // - the selected file changes (always reset), or
  // - the backend text changes while the div isn't focused (e.g. after sanitise)
  useEffect(() => {
    if (!divRef.current) return
    const switching = lastFileId.current !== file.id
    // Once the server echoes our last save, stop guarding.
    if (dirtyRef.current && bestText === lastSentRef.current) dirtyRef.current = false
    const focused = document.activeElement === divRef.current
    // Never clobber the editor while the user is typing OR while a local edit
    // is still unsaved — a stale in-flight refetch must not revert keystrokes.
    if (switching || (!focused && !dirtyRef.current)) {
      if (hasImages) {
        divRef.current.innerHTML = textToHtml(bestText ?? '', file.id)
      } else {
        divRef.current.innerText = bestText ?? ''
      }
      lastFileId.current = file.id
      if (switching) { dirtyRef.current = false; lastSentRef.current = null }
    }
  }, [file.id, bestText]) // eslint-disable-line react-hooks/exhaustive-deps

  // Extract text from contentEditable, restoring image markers from data attributes
  function extractTextWithMarkers(el: HTMLDivElement): string {
    let result = ''
    for (const node of Array.from(el.childNodes)) {
      if (node.nodeType === Node.TEXT_NODE) {
        result += node.textContent ?? ''
      } else if (node.nodeName === 'BR') {
        result += '\n'
      } else if (node.nodeName === 'IMG') {
        const marker = (node as HTMLElement).getAttribute('data-marker')
        if (marker) result += marker
      } else if (node.nodeType === Node.ELEMENT_NODE) {
        // Recurse for other elements (e.g. <div> line wraps from contentEditable)
        const inner = extractTextWithMarkers(node as HTMLDivElement)
        result += inner
      }
    }
    return result
  }

  const scheduleSave = useCallback(() => {
    dirtyRef.current = true
    if (saveTimer.current) clearTimeout(saveTimer.current)
    saveTimer.current = setTimeout(() => {
      if (!divRef.current) return
      const text = hasImages ? extractTextWithMarkers(divRef.current) : (divRef.current.innerText ?? '')
      lastSentRef.current = text
      const field = file.sanitised != null ? 'sanitised' : file.enhanced_copyedit != null ? 'copyedit' : 'transcript'
      onBodySave(text, field)
    }, 1500)
  }, [file.enhanced_copyedit, file.sanitised, onBodySave, hasImages])

  // Show floating toolbar when text is selected within this div
  function handleMouseUp() {
    // Small delay so the selection is settled
    setTimeout(() => {
      const sel = window.getSelection()
      if (!sel || sel.isCollapsed || !sel.rangeCount) {
        setToolbarPos(null)
        setSelectedWord(null)
        return
      }
      const text = sel.toString().trim()
      if (!text || !divRef.current) {
        setToolbarPos(null)
        setSelectedWord(null)
        return
      }
      // Only show if selection is within our div
      const range = sel.getRangeAt(0)
      if (!divRef.current.contains(range.commonAncestorContainer)) {
        setToolbarPos(null)
        setSelectedWord(null)
        return
      }
      const rect = range.getBoundingClientRect()
      // Position toolbar centred above the selection
      setToolbarPos({ x: rect.left + rect.width / 2, y: rect.top - 8 })
      setSelectedWord(text)
    }, 10)
  }

  // Hide toolbar when clicking outside it
  useEffect(() => {
    function onMouseDown(e: MouseEvent) {
      if (toolbarRef.current && toolbarRef.current.contains(e.target as Node)) return
      setToolbarPos(null)
      setSelectedWord(null)
    }
    document.addEventListener('mousedown', onMouseDown)
    return () => document.removeEventListener('mousedown', onMouseDown)
  }, [])

  if (!transcribed && !isAppleNote) {
    return <TranscribePlaceholder file={file} onTranscribe={onTranscribe} />
  }
  if (!bestText) {
    return <div className="flex items-center justify-center py-16 text-text-muted text-sm">No text available</div>
  }

  return (
    <>
      <div
        ref={divRef}
        contentEditable
        suppressContentEditableWarning
        onInput={scheduleSave}
        onMouseUp={handleMouseUp}
        onClick={(e) => {
          const target = e.target as HTMLElement
          if (target.tagName === 'IMG') {
            e.preventDefault()
            setLightboxSrc({ src: (target as HTMLImageElement).src, alt: (target as HTMLImageElement).alt })
          }
        }}
        className="text-[15px] leading-[1.75] text-text-primary outline-none min-h-[200px] cursor-text"
        style={{ whiteSpace: 'pre-wrap' }}
      />

      {/* Floating selection toolbar */}
      {toolbarPos && selectedWord && !showAddName && (
        <div
          ref={toolbarRef}
          style={{
            position: 'fixed',
            left: toolbarPos.x,
            top: toolbarPos.y,
            transform: 'translate(-50%, -100%)',
            zIndex: 200,
          }}
        >
          <button
            onMouseDown={e => {
              // Prevent mousedown from collapsing selection before we read it
              e.preventDefault()
              setModalWord(selectedWord) // lock in the word before toolbar clears
              setShowAddName(true)
              setToolbarPos(null)
            }}
            className="px-3 py-1.5 rounded-lg bg-surface border border-border/[0.3] text-[12px] font-medium text-text-primary shadow-lg hover:bg-white/[0.08] transition-colors whitespace-nowrap flex items-center gap-1.5 animate-modal-in"
          >
            <span className="text-accent">+</span> Add name
          </button>
        </div>
      )}

      {/* Add Name modal — uses modalWord (locked at open time), not selectedWord */}
      {showAddName && modalWord && (
        <AddNameModal
          selectedText={modalWord}
          onClose={() => {
            setShowAddName(false)
            setModalWord(null)
            setSelectedWord(null)
          }}
        />
      )}

      {/* Image lightbox — click thumbnail to enlarge, click/Esc to close */}
      {lightboxSrc && (
        <ImageLightbox src={lightboxSrc.src} alt={lightboxSrc.alt} onClose={() => setLightboxSrc(null)} />
      )}
    </>
  )
}
