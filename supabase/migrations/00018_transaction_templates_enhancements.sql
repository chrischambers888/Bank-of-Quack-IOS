-- Transaction Templates Enhancements
-- Adds additional fields to support more complete template functionality
--------------------------------------------------------------------------------

-- Add missing columns to transaction_templates table
ALTER TABLE public.transaction_templates
  ADD COLUMN IF NOT EXISTS paid_by_member_id UUID REFERENCES public.household_members(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS paid_by_type TEXT DEFAULT 'single' CHECK (paid_by_type IN ('single', 'shared', 'custom')),
  ADD COLUMN IF NOT EXISTS split_member_id UUID REFERENCES public.household_members(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS excluded_from_budget BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS sort_order INTEGER DEFAULT 0;

-- Create index for faster lookups by household
CREATE INDEX IF NOT EXISTS idx_transaction_templates_sort_order 
  ON public.transaction_templates(household_id, sort_order);


