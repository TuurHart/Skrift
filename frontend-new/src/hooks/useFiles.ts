import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useCallback } from 'react'
import { api } from '@/api'
import type { PipelineFile } from '@/types/pipeline'
import type { CurrentBatchResponse } from '@/api'

// Single source of truth for all file state. The list endpoint returns full
// PipelineFile objects, so the selected file and the enhance-lock are derived
// from this one query instead of separate polling loops.
export const FILES_KEY = ['files'] as const
export const CURRENT_BATCH_KEY = ['currentBatch'] as const

function anyProcessing(files: PipelineFile[] | undefined): boolean {
  return !!files?.some(f =>
    f.steps.transcribe === 'processing' ||
    f.steps.sanitise === 'processing' ||
    f.steps.enhance === 'processing' ||
    f.steps.export === 'processing',
  )
}

/** All files. Polls every 1s only while something is processing; otherwise
 *  stays put and is refreshed by mutation invalidation. */
export function useFiles() {
  return useQuery({
    queryKey: FILES_KEY,
    queryFn: () => api.getFiles(),
    refetchInterval: (query) => (anyProcessing(query.state.data) ? 1000 : false),
  })
}

/** Current batch/run state. Polls every 1s only while a batch is active. */
export function useCurrentBatch() {
  return useQuery({
    queryKey: CURRENT_BATCH_KEY,
    queryFn: () => api.getCurrentBatch(),
    refetchInterval: (query) => (query.state.data?.active ? 1000 : false),
  })
}

export type CurrentBatch = CurrentBatchResponse

/** Helpers to mutate the files cache without waiting for a refetch — used to
 *  keep the editor and inspector from reverting under an in-flight poll. */
export function useFilesCache() {
  const qc = useQueryClient()

  const patchFile = useCallback((id: string, patch: Partial<PipelineFile>) => {
    qc.setQueryData<PipelineFile[]>(FILES_KEY, (prev) =>
      prev?.map(f => (f.id === id ? { ...f, ...patch } : f)),
    )
  }, [qc])

  const replaceFile = useCallback((updated: PipelineFile) => {
    qc.setQueryData<PipelineFile[]>(FILES_KEY, (prev) => {
      if (!prev) return prev
      const exists = prev.some(f => f.id === updated.id)
      return exists ? prev.map(f => (f.id === updated.id ? updated : f)) : [...prev, updated]
    })
  }, [qc])

  const invalidateFiles = useCallback(() => {
    void qc.invalidateQueries({ queryKey: FILES_KEY })
  }, [qc])

  return { patchFile, replaceFile, invalidateFiles }
}
