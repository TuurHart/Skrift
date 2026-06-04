import { type ComponentProps } from 'react'
import { Toaster as Sonner } from 'sonner'

// App-styled toast surface. Mount once near the root; trigger with toast() from
// 'sonner' anywhere.
export function Toaster(props: ComponentProps<typeof Sonner>) {
  return (
    <Sonner
      theme="dark"
      position="bottom-right"
      toastOptions={{
        classNames: {
          toast: 'bg-surface border border-border/[0.2] text-text-primary text-[13px] rounded-lg shadow-2xl',
          description: 'text-text-secondary',
          actionButton: 'bg-accent text-white',
          cancelButton: 'bg-white/[0.06] text-text-secondary',
          error: 'text-destructive',
        },
      }}
      {...props}
    />
  )
}
