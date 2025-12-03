-- Quack App - Managed Members Support
-- Allows users to create household members for people without their own accounts
-- (e.g., children, elderly relatives). These can later be claimed via unique code.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- SCHEMA CHANGES: Make user_id nullable, add managed_by and claim_code
--------------------------------------------------------------------------------

-- Drop the NOT NULL constraint on user_id
ALTER TABLE public.household_members
ALTER COLUMN user_id DROP NOT NULL;

-- Add managed_by_user_id column (tracks who manages this member)
ALTER TABLE public.household_members
ADD COLUMN managed_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- Add claim_code column (unique code for transferring ownership)
ALTER TABLE public.household_members
ADD COLUMN claim_code TEXT UNIQUE;

-- Index for faster claim code lookups
CREATE INDEX idx_household_members_claim_code ON public.household_members(claim_code) WHERE claim_code IS NOT NULL;

-- Index for managed_by lookups
CREATE INDEX idx_household_members_managed_by ON public.household_members(managed_by_user_id) WHERE managed_by_user_id IS NOT NULL;

--------------------------------------------------------------------------------
-- UPDATE UNIQUE CONSTRAINT
-- Allow multiple managed members (null user_id) in same household
--------------------------------------------------------------------------------

-- Drop the old unique constraint that doesn't handle nulls well
ALTER TABLE public.household_members
DROP CONSTRAINT IF EXISTS household_members_household_id_user_id_key;

-- Create a partial unique index for non-null user_ids only
CREATE UNIQUE INDEX idx_household_members_household_user_unique 
ON public.household_members(household_id, user_id) 
WHERE user_id IS NOT NULL;

--------------------------------------------------------------------------------
-- RLS POLICY UPDATES
-- Allow managers to manage their managed members
--------------------------------------------------------------------------------

-- Drop existing update policy and create more flexible one
DROP POLICY IF EXISTS "Members can update their own profile" ON public.household_members;

CREATE POLICY "Members can update own or managed profiles" ON public.household_members
FOR UPDATE USING (
  user_id = auth.uid() 
  OR managed_by_user_id = auth.uid()
);

-- Allow managers to insert managed members
DROP POLICY IF EXISTS "Users can join households" ON public.household_members;

CREATE POLICY "Users can join or create managed members" ON public.household_members
FOR INSERT WITH CHECK (
  user_id = auth.uid()  -- Regular join
  OR (user_id IS NULL AND managed_by_user_id = auth.uid())  -- Creating managed member
);

--------------------------------------------------------------------------------
-- FUNCTION: Create Managed Member
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_managed_member(
  p_household_id UUID,
  p_display_name TEXT,
  p_color TEXT DEFAULT '#26A69A'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_member_id UUID;
  v_claim_code TEXT;
  v_user_role TEXT;
BEGIN
  -- Verify user is a member of this household with appropriate role
  SELECT role INTO v_user_role
  FROM public.household_members
  WHERE household_id = p_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_user_role IS NULL THEN
    RAISE EXCEPTION 'You must be an approved member of this household';
  END IF;
  
  -- Only owners and admins can create managed members
  IF v_user_role NOT IN ('owner', 'admin') THEN
    RAISE EXCEPTION 'Only owners and admins can create managed members';
  END IF;
  
  -- Generate unique claim code (8 characters, uppercase alphanumeric)
  -- Note: Using extensions.gen_random_bytes() for Supabase compatibility with SET search_path = ''
  v_claim_code := upper(encode(extensions.gen_random_bytes(4), 'hex'));
  
  -- Ensure claim code is unique (regenerate if collision)
  WHILE EXISTS (SELECT 1 FROM public.household_members WHERE claim_code = v_claim_code) LOOP
    v_claim_code := upper(encode(extensions.gen_random_bytes(4), 'hex'));
  END LOOP;
  
  -- Create the managed member
  INSERT INTO public.household_members (
    household_id, 
    user_id, 
    display_name, 
    role, 
    color, 
    status,
    managed_by_user_id,
    claim_code
  )
  VALUES (
    p_household_id,
    NULL,  -- No user account
    p_display_name,
    'member',  -- Managed members are always regular members
    p_color,
    'approved',  -- Auto-approved since created by owner/admin
    auth.uid(),
    v_claim_code
  )
  RETURNING id INTO v_member_id;
  
  RETURN v_member_id;
END;
$$;

--------------------------------------------------------------------------------
-- FUNCTION: Claim Managed Member
-- Links an authenticated user to a managed member via claim code
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.claim_managed_member(
  p_claim_code TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_member_id UUID;
  v_household_id UUID;
  v_existing_status TEXT;
BEGIN
  -- Find the managed member by claim code
  SELECT id, household_id INTO v_member_id, v_household_id
  FROM public.household_members
  WHERE claim_code = upper(trim(p_claim_code))
    AND user_id IS NULL  -- Must be unclaimed
    AND managed_by_user_id IS NOT NULL;  -- Must be a managed member
  
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or already claimed code';
  END IF;
  
  -- Check if user already has a membership in this household
  SELECT status INTO v_existing_status
  FROM public.household_members
  WHERE household_id = v_household_id AND user_id = auth.uid();
  
  IF v_existing_status IS NOT NULL THEN
    IF v_existing_status = 'approved' THEN
      RAISE EXCEPTION 'You are already a member of this household';
    ELSIF v_existing_status = 'pending' THEN
      RAISE EXCEPTION 'You have a pending request for this household';
    ELSIF v_existing_status = 'rejected' THEN
      RAISE EXCEPTION 'Your previous request for this household was rejected';
    ELSIF v_existing_status = 'inactive' THEN
      RAISE EXCEPTION 'You were previously a member of this household. Use the household invite code to rejoin with your existing account.';
    END IF;
  END IF;
  
  -- Transfer ownership: set user_id, clear managed_by and claim_code
  UPDATE public.household_members
  SET 
    user_id = auth.uid(),
    managed_by_user_id = NULL,
    claim_code = NULL,
    updated_at = NOW()
  WHERE id = v_member_id;
  
  RETURN v_household_id;
END;
$$;

--------------------------------------------------------------------------------
-- FUNCTION: Regenerate Claim Code
-- Allows manager to generate a new claim code for their managed member
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.regenerate_claim_code(
  p_member_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_new_code TEXT;
  v_managed_by UUID;
BEGIN
  -- Verify the current user manages this member
  SELECT managed_by_user_id INTO v_managed_by
  FROM public.household_members
  WHERE id = p_member_id
    AND user_id IS NULL  -- Must still be managed (unclaimed)
    AND managed_by_user_id IS NOT NULL;
  
  IF v_managed_by IS NULL OR v_managed_by != auth.uid() THEN
    RAISE EXCEPTION 'You can only regenerate codes for members you manage';
  END IF;
  
  -- Generate new unique claim code
  v_new_code := upper(encode(extensions.gen_random_bytes(4), 'hex'));
  
  WHILE EXISTS (SELECT 1 FROM public.household_members WHERE claim_code = v_new_code) LOOP
    v_new_code := upper(encode(extensions.gen_random_bytes(4), 'hex'));
  END LOOP;
  
  -- Update the claim code
  UPDATE public.household_members
  SET claim_code = v_new_code, updated_at = NOW()
  WHERE id = p_member_id;
  
  RETURN v_new_code;
END;
$$;

--------------------------------------------------------------------------------
-- FUNCTION: Delete Managed Member
-- Allows manager to delete a managed member (if no transaction history)
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.delete_managed_member(
  p_member_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_managed_by UUID;
  v_has_transactions BOOLEAN;
BEGIN
  -- Verify the current user manages this member
  SELECT managed_by_user_id INTO v_managed_by
  FROM public.household_members
  WHERE id = p_member_id
    AND user_id IS NULL
    AND managed_by_user_id IS NOT NULL;
  
  IF v_managed_by IS NULL OR v_managed_by != auth.uid() THEN
    RAISE EXCEPTION 'You can only delete members you manage';
  END IF;
  
  -- Check if member has any transaction history
  SELECT EXISTS (
    SELECT 1 FROM public.transactions 
    WHERE paid_by_member_id = p_member_id 
       OR paid_to_member_id = p_member_id
       OR split_member_id = p_member_id
    UNION
    SELECT 1 FROM public.transaction_splits
    WHERE member_id = p_member_id
  ) INTO v_has_transactions;
  
  IF v_has_transactions THEN
    -- Set to inactive instead of deleting to preserve history
    UPDATE public.household_members
    SET status = 'inactive', updated_at = NOW()
    WHERE id = p_member_id;
  ELSE
    -- Safe to delete - no transaction history
    DELETE FROM public.household_members
    WHERE id = p_member_id;
  END IF;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- UPDATE: member_balances view to handle managed members (user_id can be NULL)
-- The existing view already works since it only joins on member_id, not user_id
-- No changes needed to the view itself
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- UPDATE: create_transaction_with_splits to include managed members in splits
--------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.create_transaction_with_splits(UUID, DATE, TEXT, NUMERIC, TEXT, UUID, UUID, UUID, TEXT, TEXT, UUID, UUID, BOOLEAN, TEXT, UUID, JSONB);

CREATE OR REPLACE FUNCTION public.create_transaction_with_splits(
  p_household_id UUID,
  p_date DATE,
  p_description TEXT,
  p_amount NUMERIC,
  p_transaction_type TEXT,
  p_paid_by_member_id UUID,
  p_paid_to_member_id UUID,
  p_category_id UUID,
  p_split_type TEXT,
  p_paid_by_type TEXT,
  p_split_member_id UUID,
  p_reimburses_transaction_id UUID,
  p_excluded_from_budget BOOLEAN,
  p_notes TEXT,
  p_created_by_user_id UUID,
  p_splits JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_transaction_id UUID;
  v_split JSONB;
  v_member_count INT;
  v_equal_share NUMERIC;
  v_member RECORD;
BEGIN
  -- Create the transaction
  INSERT INTO public.transactions (
    household_id, date, description, amount, transaction_type,
    paid_by_member_id, paid_to_member_id, category_id, split_type,
    paid_by_type, split_member_id, reimburses_transaction_id, excluded_from_budget, notes, created_by_user_id
  )
  VALUES (
    p_household_id, p_date, p_description, p_amount, p_transaction_type,
    p_paid_by_member_id, p_paid_to_member_id, p_category_id, p_split_type,
    p_paid_by_type, p_split_member_id, p_reimburses_transaction_id, p_excluded_from_budget, p_notes, p_created_by_user_id
  )
  RETURNING id INTO v_transaction_id;

  -- Only create splits for expenses
  IF p_transaction_type = 'expense' THEN
    IF p_splits IS NOT NULL AND jsonb_array_length(p_splits) > 0 THEN
      -- Use provided custom splits
      FOR v_split IN SELECT * FROM jsonb_array_elements(p_splits)
      LOOP
        INSERT INTO public.transaction_splits (
          transaction_id, member_id, amount, percentage, 
          owed_amount, owed_percentage, paid_amount, paid_percentage
        )
        VALUES (
          v_transaction_id,
          (v_split->>'member_id')::UUID,
          COALESCE((v_split->>'owed_amount')::NUMERIC, 0),
          (v_split->>'owed_percentage')::NUMERIC,
          COALESCE((v_split->>'owed_amount')::NUMERIC, 0),
          (v_split->>'owed_percentage')::NUMERIC,
          COALESCE((v_split->>'paid_amount')::NUMERIC, 0),
          (v_split->>'paid_percentage')::NUMERIC
        );
      END LOOP;
    ELSE
      -- Auto-generate splits based on split_type and paid_by_type
      -- Include both regular and managed members (user_id IS NULL or NOT NULL)
      SELECT COUNT(*) INTO v_member_count
      FROM public.household_members
      WHERE household_id = p_household_id AND status = 'approved';
      
      v_equal_share := p_amount / GREATEST(v_member_count, 1);
      
      FOR v_member IN 
        SELECT id FROM public.household_members 
        WHERE household_id = p_household_id AND status = 'approved'
      LOOP
        INSERT INTO public.transaction_splits (
          transaction_id, member_id, amount, owed_amount, owed_percentage, paid_amount, paid_percentage
        )
        VALUES (
          v_transaction_id,
          v_member.id,
          CASE 
            WHEN p_split_type = 'equal' THEN v_equal_share
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN p_amount
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN p_amount
            ELSE 0
          END,
          CASE 
            WHEN p_split_type = 'equal' THEN v_equal_share
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN p_amount
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN p_amount
            ELSE 0
          END,
          CASE 
            WHEN p_split_type = 'equal' THEN 100.0 / v_member_count
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN 100
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN 100
            ELSE 0
          END,
          CASE 
            WHEN p_paid_by_type = 'single' AND v_member.id = p_paid_by_member_id THEN p_amount
            WHEN p_paid_by_type = 'shared' THEN v_equal_share
            ELSE 0
          END,
          CASE 
            WHEN p_paid_by_type = 'single' AND v_member.id = p_paid_by_member_id THEN 100
            WHEN p_paid_by_type = 'shared' THEN 100.0 / v_member_count
            ELSE 0
          END
        );
      END LOOP;
    END IF;
  END IF;
  
  RETURN v_transaction_id;
END;
$$;

--------------------------------------------------------------------------------
-- FUNCTION: Check Inactive Membership
-- Returns member info if user has an inactive membership for the given invite code
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.check_inactive_membership(
  p_invite_code TEXT
)
RETURNS TABLE (
  member_id UUID,
  display_name TEXT,
  household_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id UUID;
BEGIN
  -- Find household by invite code
  SELECT id INTO v_household_id
  FROM public.households
  WHERE invite_code = p_invite_code;
  
  IF v_household_id IS NULL THEN
    RETURN;  -- Return empty if invalid code
  END IF;
  
  -- Check for inactive membership
  RETURN QUERY
  SELECT 
    hm.id,
    hm.display_name,
    h.name
  FROM public.household_members hm
  JOIN public.households h ON h.id = hm.household_id
  WHERE hm.household_id = v_household_id 
    AND hm.user_id = auth.uid()
    AND hm.status = 'inactive';
END;
$$;

--------------------------------------------------------------------------------
-- Done! Managed members support is now active.
--------------------------------------------------------------------------------

