-- Quack App - Member Permissions System
-- Simplifies roles to owner/member only, adds granular per-member permissions
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- STEP 1: Create member_permissions table
--------------------------------------------------------------------------------

CREATE TABLE public.member_permissions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  member_id UUID NOT NULL UNIQUE REFERENCES public.household_members(id) ON DELETE CASCADE,
  can_create_managed_members BOOLEAN NOT NULL DEFAULT FALSE,
  can_remove_members BOOLEAN NOT NULL DEFAULT FALSE,
  can_reactivate_members BOOLEAN NOT NULL DEFAULT FALSE,
  can_approve_join_requests BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for faster lookups
CREATE INDEX idx_member_permissions_member_id ON public.member_permissions(member_id);

-- Enable RLS
ALTER TABLE public.member_permissions ENABLE ROW LEVEL SECURITY;

-- RLS policies for member_permissions
CREATE POLICY "Members can view permissions in their household" ON public.member_permissions
  FOR SELECT USING (
    member_id IN (
      SELECT id FROM public.household_members 
      WHERE household_id IN (SELECT public.user_household_ids())
    )
  );

CREATE POLICY "Owners can manage permissions" ON public.member_permissions
  FOR ALL USING (
    member_id IN (
      SELECT hm.id FROM public.household_members hm
      WHERE hm.household_id IN (
        SELECT household_id FROM public.household_members 
        WHERE user_id = auth.uid() AND role = 'owner' AND status = 'approved'
      )
    )
  );

-- Trigger for updated_at
CREATE TRIGGER update_member_permissions_updated_at
  BEFORE UPDATE ON public.member_permissions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

--------------------------------------------------------------------------------
-- STEP 2: Migrate existing admin roles to member
--------------------------------------------------------------------------------

UPDATE public.household_members
SET role = 'member', updated_at = NOW()
WHERE role = 'admin';

--------------------------------------------------------------------------------
-- STEP 3: Update role CHECK constraint (remove admin)
--------------------------------------------------------------------------------

-- Drop the existing check constraint
ALTER TABLE public.household_members
DROP CONSTRAINT IF EXISTS household_members_role_check;

-- Add new constraint with only owner and member
ALTER TABLE public.household_members
ADD CONSTRAINT household_members_role_check CHECK (role IN ('owner', 'member'));

--------------------------------------------------------------------------------
-- STEP 4: Helper function to check if user has a specific permission
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.member_has_permission(
  p_member_id UUID,
  p_permission TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role TEXT;
  v_has_permission BOOLEAN := FALSE;
BEGIN
  -- Get the member's role
  SELECT role INTO v_role
  FROM public.household_members
  WHERE id = p_member_id AND status = 'approved';
  
  -- Owners always have all permissions
  IF v_role = 'owner' THEN
    RETURN TRUE;
  END IF;
  
  -- Check specific permission for non-owners
  EXECUTE format(
    'SELECT COALESCE(%I, FALSE) FROM public.member_permissions WHERE member_id = $1',
    p_permission
  ) INTO v_has_permission USING p_member_id;
  
  RETURN COALESCE(v_has_permission, FALSE);
END;
$$;

--------------------------------------------------------------------------------
-- STEP 5: RPC Functions for managing permissions
--------------------------------------------------------------------------------

-- Get permissions for a member
CREATE OR REPLACE FUNCTION public.get_member_permissions(
  p_member_id UUID
)
RETURNS TABLE (
  member_id UUID,
  can_create_managed_members BOOLEAN,
  can_remove_members BOOLEAN,
  can_reactivate_members BOOLEAN,
  can_approve_join_requests BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id UUID;
BEGIN
  -- Get the household for this member
  SELECT household_id INTO v_household_id
  FROM public.household_members
  WHERE id = p_member_id;
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;
  
  -- Verify caller is a member of the same household
  IF NOT EXISTS (
    SELECT 1 FROM public.household_members
    WHERE household_id = v_household_id AND user_id = auth.uid() AND status = 'approved'
  ) THEN
    RAISE EXCEPTION 'Not authorized to view permissions';
  END IF;
  
  -- Return permissions (with defaults if no record exists)
  RETURN QUERY
  SELECT 
    p_member_id,
    COALESCE(mp.can_create_managed_members, FALSE),
    COALESCE(mp.can_remove_members, FALSE),
    COALESCE(mp.can_reactivate_members, FALSE),
    COALESCE(mp.can_approve_join_requests, FALSE)
  FROM (SELECT 1) dummy
  LEFT JOIN public.member_permissions mp ON mp.member_id = p_member_id;
END;
$$;

-- Update permissions for a member (owner only)
CREATE OR REPLACE FUNCTION public.update_member_permissions(
  p_member_id UUID,
  p_can_create_managed_members BOOLEAN DEFAULT NULL,
  p_can_remove_members BOOLEAN DEFAULT NULL,
  p_can_reactivate_members BOOLEAN DEFAULT NULL,
  p_can_approve_join_requests BOOLEAN DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id UUID;
  v_target_role TEXT;
  v_caller_role TEXT;
BEGIN
  -- Get info about the target member
  SELECT household_id, role INTO v_household_id, v_target_role
  FROM public.household_members
  WHERE id = p_member_id AND status = 'approved';
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Member not found or not active';
  END IF;
  
  -- Cannot modify owner permissions
  IF v_target_role = 'owner' THEN
    RAISE EXCEPTION 'Cannot modify owner permissions';
  END IF;
  
  -- Verify caller is the owner of this household
  SELECT role INTO v_caller_role
  FROM public.household_members
  WHERE household_id = v_household_id AND user_id = auth.uid() AND status = 'approved';
  
  IF v_caller_role IS NULL OR v_caller_role != 'owner' THEN
    RAISE EXCEPTION 'Only the household owner can modify permissions';
  END IF;
  
  -- Insert or update permissions
  INSERT INTO public.member_permissions (
    member_id,
    can_create_managed_members,
    can_remove_members,
    can_reactivate_members,
    can_approve_join_requests
  )
  VALUES (
    p_member_id,
    COALESCE(p_can_create_managed_members, FALSE),
    COALESCE(p_can_remove_members, FALSE),
    COALESCE(p_can_reactivate_members, FALSE),
    COALESCE(p_can_approve_join_requests, FALSE)
  )
  ON CONFLICT (member_id) DO UPDATE SET
    can_create_managed_members = COALESCE(p_can_create_managed_members, member_permissions.can_create_managed_members),
    can_remove_members = COALESCE(p_can_remove_members, member_permissions.can_remove_members),
    can_reactivate_members = COALESCE(p_can_reactivate_members, member_permissions.can_reactivate_members),
    can_approve_join_requests = COALESCE(p_can_approve_join_requests, member_permissions.can_approve_join_requests),
    updated_at = NOW();
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- STEP 6: Update reactivate_member to clear permissions on reactivation
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
  
  -- Clear any existing permissions (reset to defaults)
  DELETE FROM public.member_permissions
  WHERE member_id = p_member_id;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- STEP 7: Update approve_member to use permissions
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.approve_member(p_member_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id UUID;
  v_caller_member_id UUID;
BEGIN
  -- Get the household ID for this member
  SELECT household_id INTO v_household_id
  FROM public.household_members
  WHERE id = p_member_id AND status = 'pending';
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Member not found or not pending';
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
  
  -- Check if caller has permission (owner always has, otherwise check permissions)
  IF NOT public.member_has_permission(v_caller_member_id, 'can_approve_join_requests') THEN
    RAISE EXCEPTION 'You do not have permission to approve members';
  END IF;
  
  -- Approve the member
  UPDATE public.household_members
  SET status = 'approved', updated_at = NOW()
  WHERE id = p_member_id;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- STEP 8: Update reject_member to use permissions
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.reject_member(p_member_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id UUID;
  v_caller_member_id UUID;
BEGIN
  -- Get the household ID for this member
  SELECT household_id INTO v_household_id
  FROM public.household_members
  WHERE id = p_member_id AND status = 'pending';
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Member not found or not pending';
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
  
  -- Check if caller has permission
  IF NOT public.member_has_permission(v_caller_member_id, 'can_approve_join_requests') THEN
    RAISE EXCEPTION 'You do not have permission to reject members';
  END IF;
  
  -- Delete the pending member
  DELETE FROM public.household_members
  WHERE id = p_member_id;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- STEP 9: Update get_pending_members to use permissions
--------------------------------------------------------------------------------

-- Drop existing function first (return type is changing)
DROP FUNCTION IF EXISTS public.get_pending_members(UUID);

CREATE OR REPLACE FUNCTION public.get_pending_members(p_household_id UUID)
RETURNS TABLE(
  id UUID,
  household_id UUID,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  role TEXT,
  color TEXT,
  status TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  managed_by_user_id UUID,
  claim_code TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id UUID;
BEGIN
  -- Get caller's member ID
  SELECT hm.id INTO v_caller_member_id
  FROM public.household_members hm
  WHERE hm.household_id = p_household_id 
    AND hm.user_id = auth.uid() 
    AND hm.status = 'approved';
  
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'You are not an active member of this household';
  END IF;
  
  -- Check if caller has permission
  IF NOT public.member_has_permission(v_caller_member_id, 'can_approve_join_requests') THEN
    RAISE EXCEPTION 'You do not have permission to view pending members';
  END IF;
  
  -- Return pending members
  RETURN QUERY
  SELECT 
    hm.id,
    hm.household_id,
    hm.user_id,
    hm.display_name,
    hm.avatar_url,
    hm.role,
    hm.color,
    hm.status,
    hm.created_at,
    hm.updated_at,
    hm.managed_by_user_id,
    hm.claim_code
  FROM public.household_members hm
  WHERE hm.household_id = p_household_id AND hm.status = 'pending'
  ORDER BY hm.created_at;
END;
$$;

--------------------------------------------------------------------------------
-- STEP 10: Update create_managed_member to use permissions
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
  v_caller_member_id UUID;
BEGIN
  -- Get caller's member ID
  SELECT id INTO v_caller_member_id
  FROM public.household_members
  WHERE household_id = p_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'You must be an approved member of this household';
  END IF;
  
  -- Check if caller has permission
  IF NOT public.member_has_permission(v_caller_member_id, 'can_create_managed_members') THEN
    RAISE EXCEPTION 'You do not have permission to create managed members';
  END IF;
  
  -- Generate unique claim code (8 characters, uppercase alphanumeric)
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
    'approved',  -- Auto-approved since created by someone with permission
    auth.uid(),
    v_claim_code
  )
  RETURNING id INTO v_member_id;
  
  RETURN v_member_id;
END;
$$;

--------------------------------------------------------------------------------
-- STEP 11: Update remove_member_from_household to use permissions
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
  v_caller_member_id UUID;
  v_has_transactions BOOLEAN;
BEGIN
  -- Get info about the target member
  SELECT household_id, role, user_id, status INTO v_household_id, v_target_role, v_target_user_id, v_target_status
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
  
  -- Check if caller has permission
  IF NOT public.member_has_permission(v_caller_member_id, 'can_remove_members') THEN
    RAISE EXCEPTION 'You do not have permission to remove members';
  END IF;
  
  -- Cannot remove yourself
  IF v_target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'You cannot remove yourself from the household';
  END IF;
  
  -- Cannot remove the owner
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
    
    -- Clear their permissions
    DELETE FROM public.member_permissions
    WHERE member_id = p_member_id;
  ELSE
    -- Safe to delete - no transaction history
    -- Permissions will be deleted via CASCADE
    DELETE FROM public.household_members
    WHERE id = p_member_id;
  END IF;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- STEP 12: Update accept_ownership_transfer to demote to member (not admin)
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
  
  -- Transfer ownership: demote current owner to member, promote new owner
  UPDATE public.household_members
  SET role = 'member', updated_at = NOW()
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
  
  -- Clear new owner's permissions (they're owner now, don't need them)
  DELETE FROM public.member_permissions
  WHERE member_id = v_caller_member_id;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- Done! Member permissions system is now active.
--------------------------------------------------------------------------------

