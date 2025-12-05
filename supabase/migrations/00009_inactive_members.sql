-- Quack App - Inactive Member Support
-- Allows users to leave households while preserving their historical data
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- UPDATE STATUS CONSTRAINT TO INCLUDE 'inactive'
--------------------------------------------------------------------------------

-- Drop the existing constraint and add the new one with 'inactive' status
ALTER TABLE public.household_members 
DROP CONSTRAINT IF EXISTS household_members_status_check;

ALTER TABLE public.household_members 
ADD CONSTRAINT household_members_status_check 
CHECK (status IN ('pending', 'approved', 'rejected', 'inactive'));

--------------------------------------------------------------------------------
-- UPDATE JOIN_HOUSEHOLD FUNCTION
-- Reactivate inactive members instead of blocking them
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.join_household(
  p_invite_code TEXT,
  p_display_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id UUID;
  v_existing_status TEXT;
  v_member_id UUID;
BEGIN
  -- Find household by invite code
  SELECT id INTO v_household_id
  FROM public.households
  WHERE invite_code = p_invite_code;
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Invalid invite code';
  END IF;
  
  -- Check if already a member (in any status)
  SELECT status, id INTO v_existing_status, v_member_id
  FROM public.household_members 
  WHERE household_id = v_household_id AND user_id = auth.uid();
  
  IF v_existing_status IS NOT NULL THEN
    IF v_existing_status = 'pending' THEN
      RAISE EXCEPTION 'Your request to join is pending approval';
    ELSIF v_existing_status = 'rejected' THEN
      RAISE EXCEPTION 'Your request to join was declined';
    ELSIF v_existing_status = 'inactive' THEN
      -- Reactivate the inactive member
      UPDATE public.household_members
      SET status = 'approved', 
          display_name = p_display_name,
          updated_at = NOW()
      WHERE id = v_member_id;
      
      RETURN v_household_id;
    ELSE
      RAISE EXCEPTION 'Already a member of this household';
    END IF;
  END IF;
  
  -- Add as pending member
  INSERT INTO public.household_members (household_id, user_id, display_name, role, status)
  VALUES (v_household_id, auth.uid(), p_display_name, 'member', 'pending');
  
  RETURN v_household_id;
END;
$$;

--------------------------------------------------------------------------------
-- ADD FUNCTION TO LEAVE HOUSEHOLD
-- Sets member status to 'inactive' to preserve historical data
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.leave_household(p_household_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_member_id UUID;
  v_member_role TEXT;
  v_approved_count INTEGER;
BEGIN
  -- Get the member record for the current user in this household
  SELECT id, role INTO v_member_id, v_member_role
  FROM public.household_members
  WHERE household_id = p_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'You are not an active member of this household';
  END IF;
  
  -- Owners cannot leave (they must delete the household or transfer ownership)
  IF v_member_role = 'owner' THEN
    RAISE EXCEPTION 'Owners cannot leave the household. Delete the household or transfer ownership first.';
  END IF;
  
  -- Count remaining approved members (excluding the one leaving)
  SELECT COUNT(*) INTO v_approved_count
  FROM public.household_members
  WHERE household_id = p_household_id 
    AND status = 'approved'
    AND id != v_member_id;
  
  -- Ensure at least one member remains
  IF v_approved_count < 1 THEN
    RAISE EXCEPTION 'Cannot leave: you are the last active member';
  END IF;
  
  -- Set member status to inactive
  UPDATE public.household_members
  SET status = 'inactive', updated_at = NOW()
  WHERE id = v_member_id;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- Done! Inactive member support is now active.
--------------------------------------------------------------------------------



