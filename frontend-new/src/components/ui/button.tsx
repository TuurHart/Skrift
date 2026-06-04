import * as React from 'react'
import { Slot } from '@radix-ui/react-slot'
import { cva, type VariantProps } from 'class-variance-authority'
import { cn } from '@/lib/utils'

// Variants mirror the app's existing button styling (bg-accent / destructive /
// subtle white surfaces) so adoption is a drop-in, not a restyle.
const buttonVariants = cva(
  'inline-flex items-center justify-center gap-1.5 rounded-md font-medium transition-all duration-150 disabled:opacity-60 disabled:pointer-events-none active:scale-[0.98] outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
  {
    variants: {
      variant: {
        default: 'bg-accent text-white hover:bg-accent/90 hover:shadow-md hover:shadow-accent/20',
        destructive: 'bg-destructive text-white hover:opacity-90',
        secondary: 'bg-white/[0.05] border border-border/[0.15] text-text-secondary hover:text-text-primary hover:bg-white/[0.08]',
        ghost: 'text-text-secondary hover:text-text-primary hover:bg-white/[0.05]',
      },
      size: {
        default: 'px-3 py-1.5 text-[12px]',
        sm: 'px-2 py-1 text-[11px]',
        lg: 'px-4 py-2.5 text-[14px]',
        icon: 'p-[5px]',
      },
    },
    defaultVariants: { variant: 'default', size: 'default' },
  },
)

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean
}

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : 'button'
    return <Comp className={cn(buttonVariants({ variant, size }), className)} ref={ref} {...props} />
  },
)
Button.displayName = 'Button'

export { buttonVariants }
