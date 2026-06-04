export type StepStatus = 'pending' | 'processing' | 'done' | 'error' | 'skipped'

export interface ProcessingSteps {
  transcribe: StepStatus
  sanitise: StepStatus
  enhance: StepStatus
  export: StepStatus
}

export interface PhoneLocation {
  placeName?: string
  latitude?: number
  longitude?: number
}

export interface PhoneWeather {
  conditions?: string
  temperature?: number
  temperatureUnit?: string
}

export interface PhonePressure {
  hPa?: number
  trend?: string
}

export interface PhoneDaylight {
  sunrise?: string
  sunset?: string
  hoursOfLight?: number
}

export interface SharedContent {
  type: 'url' | 'image' | 'text' | 'file'
  url?: string
  urlTitle?: string
  urlDescription?: string
  text?: string
  fileName?: string
}

export interface AudioMetadata {
  duration?: string
  format?: string
  source?: string
  phone_location?: PhoneLocation
  phone_weather?: PhoneWeather
  phone_pressure?: PhonePressure
  phone_day_period?: string
  phone_daylight?: PhoneDaylight
  phone_steps?: number
  phone_photo?: string
  phone_photo_size?: number
  shared_content?: SharedContent
  shared_attachment?: string
  shared_attachment_name?: string
  [key: string]: unknown
}

export interface PipelineFile {
  id: string
  filename: string
  path: string
  size: number
  conversationMode: boolean
  steps: ProcessingSteps
  uploadedAt: string
  lastModified: string | null
  lastActivityAt: string | null
  transcript: string | null
  sanitised: string | null
  exported: string | null
  enhanced_title: string | null
  title_approval_status: string | null
  enhanced_copyedit: string | null
  enhanced_summary: string | null
  enhanced_tags: string[] | null
  tag_suggestions: Record<string, string[]> | null
  /** Currently streaming enhance step (transient). Null when idle. */
  enhance_step: 'title' | 'copy_edit' | 'summary' | 'tags' | null
  source_type: 'audio' | 'note' | 'capture' | null
  compiled_text: string | null
  include_audio_in_export: boolean | null
  error: string | null
  errorDetails: Record<string, unknown> | null
  processingTime: Record<string, number> | null
  audioMetadata: AudioMetadata | null
  progress: number | null
  progressMessage: string | null
  significance: number | null
}

export interface UploadResponse {
  success: boolean
  files: PipelineFile[]
  message: string
  errors: string[]
}

export interface SystemHealth {
  status: string
  resources?: {
    cpuUsage?: number
    ramUsed?: number
    ramTotal?: number
  }
  processing?: {
    active?: boolean
    currentFile?: string | null
  }
  file_statistics?: {
    total?: number
    by_status?: Record<string, number>
  }
  transcription_modules?: {
    parakeet?: { available?: boolean; engine?: string }
    [key: string]: { available?: boolean; [k: string]: unknown } | undefined
  }
  mlx_model?: {
    selected?: string | null
    loaded?: boolean
  }
}
