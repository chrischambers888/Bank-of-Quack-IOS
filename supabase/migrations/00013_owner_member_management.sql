-- Quack App - Owner Member Management
-- Allows household owners to remove members from household
-- Automatically handles: deletes if no transactions, sets inactive if has transactions
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- FUNCTION: Remove Member from Household
-- Removes a member from the household:
-- - If no transactions: completely deletes the membership record
-- - If has transactions: sets them to inactive to preserve history
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.remove_member_from_household(
  p_member_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id UUID;
  v_target_role TEXT;
  v_target_user_id UUID;
  v_target_status TEXT;
  v_caller_role TEXT;
  v_has_transactions BOOLEAN;
BEGIN
  -- Get info about the target member
  SELECT household_id, role, user_id, status INTO v_household_id, v_target_role, v_target_user_id, v_target_status
  FROM public.household_members
  WHERE id = p_member_id;
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;
  
  -- Verify the caller is the owner of this household
  SELECT role INTO v_caller_role
  FROM public.household_members
  WHERE household_id = v_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_caller_role IS NULL OR v_caller_role != 'owner' THEN
    RAISE EXCEPTION 'Only the household owner can remove members';
  END IF;
  
  -- Cannot remove yourself (the owner)
  IF v_target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'You cannot remove yourself from the household';
  END IF;
  
  -- Cannot remove another owner
  IF v_target_role = 'owner' THEN
    RAISE EXCEPTION 'Cannot remove the household owner';
  END IF;
  
  -- Cannot remove someone already inactive
  IF v_target_status = 'inactive' THEN
    RAISE EXCEPTION 'Member is already inactive';
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
    -- Set to inactive to preserve transaction history
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
-- FUNCTION: Reactivate Member
-- Allows owner to reactivate an inactive member (sets status back to approved)
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.reactivate_member(
  p_member_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id UUID;
  v_target_status TEXT;
  v_caller_role TEXT;
BEGIN
  -- Get info about the target member
  SELECT household_id, status INTO v_household_id, v_target_status
  FROM public.household_members
  WHERE id = p_member_id;
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;
  
  -- Verify the caller is the owner of this household
  SELECT role INTO v_caller_role
  FROM public.household_members
  WHERE household_id = v_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_caller_role IS NULL OR v_caller_role != 'owner' THEN
    RAISE EXCEPTION 'Only the household owner can reactivate members';
  END IF;
  
  -- Can only reactivate inactive members
  IF v_target_status != 'inactive' THEN
    RAISE EXCEPTION 'Member is not inactive';
  END IF;
  
  -- Reactivate the member
  UPDATE public.household_members
  SET status = 'approved', updated_at = NOW()
  WHERE id = p_member_id;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- OWNERSHIP TRANSFER SYSTEM
-- Allows owner to transfer ownership to another active, non-managed member
-- Transfer is pending until accepted by the target member
--------------------------------------------------------------------------------

-- Add pending ownership transfer columns to households
ALTER TABLE public.households
ADD COLUMN IF NOT EXISTS pending_owner_member_id UUID REFERENCES public.household_members(id) ON DELETE SET NULL;

ALTER TABLE public.households
ADD COLUMN IF NOT EXISTS pending_owner_initiated_at TIMESTAMPTZ;

-- Index for faster lookups
CREATE INDEX IF NOT EXISTS idx_households_pending_owner ON public.households(pending_owner_member_id) WHERE pending_owner_member_id IS NOT NULL;

--------------------------------------------------------------------------------
-- FUNCTION: Initiate Ownership Transfer
-- Owner initiates transfer to an active, non-managed member
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.initiate_ownership_transfer(
  p_household_id UUID,
  p_target_member_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_role TEXT;
  v_caller_member_id UUID;
  v_target_user_id UUID;
  v_target_status TEXT;
  v_target_household_id UUID;
  v_existing_pending UUID;
BEGIN
  -- Verify caller is the owner of this household
  SELECT id, role INTO v_caller_member_id, v_caller_role
  FROM public.household_members
  WHERE household_id = p_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_caller_role IS NULL OR v_caller_role != 'owner' THEN
    RAISE EXCEPTION 'Only the household owner can transfer ownership';
  END IF;
  
  -- Cannot transfer to yourself
  IF v_caller_member_id = p_target_member_id THEN
    RAISE EXCEPTION 'Cannot transfer ownership to yourself';
  END IF;
  
  -- Verify target member exists, is active, non-managed, and in same household
  SELECT user_id, status, household_id INTO v_target_user_id, v_target_status, v_target_household_id
  FROM public.household_members
  WHERE id = p_target_member_id;
  
  IF v_target_household_id IS NULL OR v_target_household_id != p_household_id THEN
    RAISE EXCEPTION 'Target member not found in this household';
  END IF;
  
  IF v_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Cannot transfer ownership to a managed member';
  END IF;
  
  IF v_target_status != 'approved' THEN
    RAISE EXCEPTION 'Cannot transfer ownership to an inactive member';
  END IF;
  
  -- Check if there's already a pending transfer
  SELECT pending_owner_member_id INTO v_existing_pending
  FROM public.households
  WHERE id = p_household_id;
  
  IF v_existing_pending IS NOT NULL THEN
    RAISE EXCEPTION 'There is already a pending ownership transfer. Revoke it first.';
  END IF;
  
  -- Set pending transfer
  UPDATE public.households
  SET 
    pending_owner_member_id = p_target_member_id,
    pending_owner_initiated_at = NOW(),
    updated_at = NOW()
  WHERE id = p_household_id;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- FUNCTION: Revoke Ownership Transfer
-- Owner cancels the pending transfer
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.revoke_ownership_transfer(
  p_household_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_role TEXT;
  v_existing_pending UUID;
BEGIN
  -- Verify caller is the owner of this household
  SELECT role INTO v_caller_role
  FROM public.household_members
  WHERE household_id = p_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_caller_role IS NULL OR v_caller_role != 'owner' THEN
    RAISE EXCEPTION 'Only the household owner can revoke the transfer';
  END IF;
  
  -- Check if there's a pending transfer
  SELECT pending_owner_member_id INTO v_existing_pending
  FROM public.households
  WHERE id = p_household_id;
  
  IF v_existing_pending IS NULL THEN
    RAISE EXCEPTION 'No pending ownership transfer to revoke';
  END IF;
  
  -- Clear pending transfer
  UPDATE public.households
  SET 
    pending_owner_member_id = NULL,
    pending_owner_initiated_at = NULL,
    updated_at = NOW()
  WHERE id = p_household_id;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- FUNCTION: Accept Ownership Transfer
-- Target member accepts and becomes the new owner
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.accept_ownership_transfer(
  p_household_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_pending_member_id UUID;
  v_caller_member_id UUID;
  v_current_owner_member_id UUID;
BEGIN
  -- Get caller's member ID
  SELECT id INTO v_caller_member_id
  FROM public.household_members
  WHERE household_id = p_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'You are not an active member of this household';
  END IF;
  
  -- Check if caller is the pending owner
  SELECT pending_owner_member_id INTO v_pending_member_id
  FROM public.households
  WHERE id = p_household_id;
  
  IF v_pending_member_id IS NULL THEN
    RAISE EXCEPTION 'No pending ownership transfer';
  END IF;
  
  IF v_pending_member_id != v_caller_member_id THEN
    RAISE EXCEPTION 'You are not the designated new owner';
  END IF;
  
  -- Get current owner's member ID
  SELECT id INTO v_current_owner_member_id
  FROM public.household_members
  WHERE household_id = p_household_id 
    AND role = 'owner'
    AND status = 'approved';
  
  -- Transfer ownership: demote current owner to admin, promote new owner
  UPDATE public.household_members
  SET role = 'admin', updated_at = NOW()
  WHERE id = v_current_owner_member_id;
  
  UPDATE public.household_members
  SET role = 'owner', updated_at = NOW()
  WHERE id = v_caller_member_id;
  
  -- Clear pending transfer
  UPDATE public.households
  SET 
    pending_owner_member_id = NULL,
    pending_owner_initiated_at = NULL,
    updated_at = NOW()
  WHERE id = p_household_id;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- FUNCTION: Decline Ownership Transfer
-- Target member declines the transfer offer
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.decline_ownership_transfer(
  p_household_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_pending_member_id UUID;
  v_caller_member_id UUID;
BEGIN
  -- Get caller's member ID
  SELECT id INTO v_caller_member_id
  FROM public.household_members
  WHERE household_id = p_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'You are not an active member of this household';
  END IF;
  
  -- Check if caller is the pending owner
  SELECT pending_owner_member_id INTO v_pending_member_id
  FROM public.households
  WHERE id = p_household_id;
  
  IF v_pending_member_id IS NULL THEN
    RAISE EXCEPTION 'No pending ownership transfer';
  END IF;
  
  IF v_pending_member_id != v_caller_member_id THEN
    RAISE EXCEPTION 'You are not the designated new owner';
  END IF;
  
  -- Clear pending transfer
  UPDATE public.households
  SET 
    pending_owner_member_id = NULL,
    pending_owner_initiated_at = NULL,
    updated_at = NOW()
  WHERE id = p_household_id;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- Done! Owner member management functions are now available.
--------------------------------------------------------------------------------

