-- Quack App - Fix Ownership Transfer Validation
-- Fixes issue where accept_ownership_transfer doesn't validate current owner exists
-- before attempting to demote them, which could leave ownership state inconsistent
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
  
  -- Validate current owner exists before proceeding
  IF v_current_owner_member_id IS NULL THEN
    RAISE EXCEPTION 'Household ownership state is invalid: no current owner found';
  END IF;
  
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


