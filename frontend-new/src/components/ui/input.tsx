import * as React from 'react'
import { cn } from '@/lib/utils'

export const Input = React.forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(
  ({ className, ...props }, ref) => (
    <input
      ref={ref}
      className={cn(
        'w-full rounded-md border border-border/[0.15] bg-white/[0.04] px-2.5 py-1.5 text-[12px] text-text-secondary outline-none transition-colors placeholder:text-text-muted focus:border-accent/30 disabled:opacity-60',
        className,
      )}
      {...props}
    />
  ),
)
Input.displayName = 'Input'
