-- Quack App - Remove Managed Member Ownership
-- Changes managed member operations from owner-based to permission-based:
-- - Claim code sharing: can_approve_join_requests
-- - Remove managed member: can_remove_members  
-- - Reactivate member: can_reactivate_members
-- - Edit profile: can_create_managed_members
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- STEP 1: Update regenerate_claim_code to use can_approve_join_requests
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
  v_household_id UUID;
  v_caller_member_id UUID;
BEGIN
  -- Get the household for this managed member
  SELECT household_id INTO v_household_id
  FROM public.household_members
  WHERE id = p_member_id
    AND user_id IS NULL  -- Must still be managed (unclaimed)
    AND managed_by_user_id IS NOT NULL;  -- Must be a managed member
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Member not found or not a managed member';
  END IF;
  
  -- Get caller's member ID
  SELECT id INTO v_caller_member_id
  FROM public.household_members
  WHERE household_id = v_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'You are not an active member of this household';
  END IF;
  
  -- Check if caller has permission to approve join requests (which includes sharing claim codes)
  IF NOT public.member_has_permission(v_caller_member_id, 'can_approve_join_requests') THEN
    RAISE EXCEPTION 'You do not have permission to manage claim codes';
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
-- STEP 2: Update delete_managed_member to use can_remove_members
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
  v_household_id UUID;
  v_caller_member_id UUID;
  v_has_transactions BOOLEAN;
BEGIN
  -- Get the household for this managed member
  SELECT household_id INTO v_household_id
  FROM public.household_members
  WHERE id = p_member_id
    AND user_id IS NULL
    AND managed_by_user_id IS NOT NULL;
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Member not found or not a managed member';
  END IF;
  
  -- Get caller's member ID
  SELECT id INTO v_caller_member_id
  FROM public.household_members
  WHERE household_id = v_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'You are not an active member of this household';
  END IF;
  
  -- Check if caller has permission to remove members
  IF NOT public.member_has_permission(v_caller_member_id, 'can_remove_members') THEN
    RAISE EXCEPTION 'You do not have permission to remove members';
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
-- STEP 3: Update reactivate_member to use can_reactivate_members permission
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
  v_caller_member_id UUID;
BEGIN
  -- Get info about the target member
  SELECT household_id, status INTO v_household_id, v_target_status
  FROM public.household_members
  WHERE id = p_member_id;
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;
  
  -- Get caller's member ID
  SELECT id INTO v_caller_member_id
  FROM public.household_members
  WHERE household_id = v_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'You are not an active member of this household';
  END IF;
  
  -- Check if caller has permission to reactivate members
  IF NOT public.member_has_permission(v_caller_member_id, 'can_reactivate_members') THEN
    RAISE EXCEPTION 'You do not have permission to reactivate members';
  END IF;
  
  -- Can only reactivate inactive members
  IF v_target_status != 'inactive' THEN
    RAISE EXCEPTION 'Member is not inactive';
  END IF;
  
  -- Reactivate the member
  UPDATE public.household_members
  SET status = 'approved', updated_at = NOW()
  WHERE id = p_member_id;
  
  -- Clear any existing permissions (reset to defaults)
  DELETE FROM public.member_permissions
  WHERE member_id = p_member_id;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- STEP 4: Update RLS policy for managed member profile updates
-- Allow anyone with can_create_managed_members permission to edit profiles
--------------------------------------------------------------------------------

-- Drop the existing update policies
DROP POLICY IF EXISTS "Members can update own or managed profiles" ON public.household_members;
DROP POLICY IF EXISTS "Members can update profiles with permission" ON public.household_members;

-- Create new policy that allows:
-- 1. Users updating their own profile (user_id = auth.uid())
-- 2. Users with can_create_managed_members permission updating managed members in their household
CREATE POLICY "Members can update profiles with permission" ON public.household_members
FOR UPDATE USING (
  user_id = auth.uid()
  OR (
    -- For managed members, allow users with create_managed_members permission
    user_id IS NULL 
    AND managed_by_user_id IS NOT NULL
    AND household_id IN (
      SELECT hm.household_id 
      FROM public.household_members hm
      WHERE hm.user_id = auth.uid() 
        AND hm.status = 'approved'
        AND (
          hm.role = 'owner'
          OR EXISTS (
            SELECT 1 FROM public.member_permissions mp 
            WHERE mp.member_id = hm.id 
              AND mp.can_create_managed_members = TRUE
          )
        )
    )
  )
);

--------------------------------------------------------------------------------
-- STEP 5: Create helper function to get claim code for members with permission
-- This allows viewing claim codes without being the original creator
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_managed_member_claim_code(
  p_member_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id UUID;
  v_claim_code TEXT;
  v_caller_member_id UUID;
BEGIN
  -- Get the household and claim code for this managed member
  SELECT household_id, claim_code INTO v_household_id, v_claim_code
  FROM public.household_members
  WHERE id = p_member_id
    AND user_id IS NULL  -- Must still be managed (unclaimed)
    AND managed_by_user_id IS NOT NULL;  -- Must be a managed member
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Member not found or not a managed member';
  END IF;
  
  -- Get caller's member ID
  SELECT id INTO v_caller_member_id
  FROM public.household_members
  WHERE household_id = v_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'You are not an active member of this household';
  END IF;
  
  -- Check if caller has permission to approve join requests (which includes viewing claim codes)
  IF NOT public.member_has_permission(v_caller_member_id, 'can_approve_join_requests') THEN
    RAISE EXCEPTION 'You do not have permission to view claim codes';
  END IF;
  
  RETURN v_claim_code;
END;
$$;

--------------------------------------------------------------------------------
-- STEP 6: Create trigger to set default permissions for new approved members
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_default_member_permissions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Only create permissions for non-owner members when they become approved
  IF NEW.status = 'approved' AND NEW.role != 'owner' AND 
     (OLD IS NULL OR OLD.status != 'approved') THEN
    
    -- Insert default permissions (all TRUE except can_approve_join_requests)
    INSERT INTO public.member_permissions (
      member_id,
      can_create_managed_members,
      can_remove_members,
      can_reactivate_members,
      can_approve_join_requests
    )
    VALUES (
      NEW.id,
      TRUE,   -- can_create_managed_members
      TRUE,   -- can_remove_members
      TRUE,   -- can_reactivate_members
      FALSE   -- can_approve_join_requests (restricted)
    )
    ON CONFLICT (member_id) DO NOTHING;  -- Don't overwrite existing permissions
  END IF;
  
  RETURN NEW;
END;
$$;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trigger_set_default_member_permissions ON public.household_members;

-- Create trigger for new members and status changes
CREATE TRIGGER trigger_set_default_member_permissions
  AFTER INSERT OR UPDATE OF status ON public.household_members
  FOR EACH ROW
  EXECUTE FUNCTION public.set_default_member_permissions();

--------------------------------------------------------------------------------
-- STEP 7: Set default permissions for existing approved non-owner members
--------------------------------------------------------------------------------

INSERT INTO public.member_permissions (
  member_id,
  can_create_managed_members,
  can_remove_members,
  can_reactivate_members,
  can_approve_join_requests
)
SELECT 
  id,
  TRUE,   -- can_create_managed_members
  TRUE,   -- can_remove_members
  TRUE,   -- can_reactivate_members
  FALSE   -- can_approve_join_requests
FROM public.household_members
WHERE status = 'approved' 
  AND role != 'owner'
  AND id NOT IN (SELECT member_id FROM public.member_permissions)
ON CONFLICT (member_id) DO NOTHING;

--------------------------------------------------------------------------------
-- Done! Managed member operations now use permission-based checks.
-- New members automatically get all permissions except can_approve_join_requests.
--------------------------------------------------------------------------------

