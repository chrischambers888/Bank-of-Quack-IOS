-- Quack App - Member Approval System
-- Requires existing members to approve new join requests
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- ADD STATUS COLUMN TO HOUSEHOLD_MEMBERS
--------------------------------------------------------------------------------

-- Add status column with default 'approved' for existing members
ALTER TABLE public.household_members 
ADD COLUMN status TEXT NOT NULL DEFAULT 'approved' 
CHECK (status IN ('pending', 'approved', 'rejected'));

-- Create index for faster filtering by status
CREATE INDEX idx_household_members_status ON public.household_members(status);

--------------------------------------------------------------------------------
-- UPDATE USER_HOUSEHOLD_IDS FUNCTION
-- Only return households where the member is approved
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.user_household_ids()
RETURNS SETOF UUID
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
  SELECT household_id 
  FROM public.household_members 
  WHERE user_id = auth.uid() AND status = 'approved';
$$;

--------------------------------------------------------------------------------
-- UPDATE JOIN_HOUSEHOLD FUNCTION
-- Now creates members with 'pending' status
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
BEGIN
  -- Find household by invite code
  SELECT id INTO v_household_id
  FROM public.households
  WHERE invite_code = p_invite_code;
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Invalid invite code';
  END IF;
  
  -- Check if already a member (in any status)
  SELECT status INTO v_existing_status
  FROM public.household_members 
  WHERE household_id = v_household_id AND user_id = auth.uid();
  
  IF v_existing_status IS NOT NULL THEN
    IF v_existing_status = 'pending' THEN
      RAISE EXCEPTION 'Your request to join is pending approval';
    ELSIF v_existing_status = 'rejected' THEN
      RAISE EXCEPTION 'Your request to join was declined';
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
-- ADD FUNCTION TO APPROVE MEMBER
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.approve_member(p_member_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id UUID;
  v_requester_role TEXT;
BEGIN
  -- Get the household ID for this member
  SELECT household_id INTO v_household_id
  FROM public.household_members
  WHERE id = p_member_id AND status = 'pending';
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Member not found or not pending';
  END IF;
  
  -- Check if requester is owner or admin of the household
  SELECT role INTO v_requester_role
  FROM public.household_members
  WHERE household_id = v_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_requester_role IS NULL OR v_requester_role = 'member' THEN
    RAISE EXCEPTION 'Only owners and admins can approve members';
  END IF;
  
  -- Approve the member
  UPDATE public.household_members
  SET status = 'approved', updated_at = NOW()
  WHERE id = p_member_id;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- ADD FUNCTION TO REJECT MEMBER
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.reject_member(p_member_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id UUID;
  v_requester_role TEXT;
BEGIN
  -- Get the household ID for this member
  SELECT household_id INTO v_household_id
  FROM public.household_members
  WHERE id = p_member_id AND status = 'pending';
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Member not found or not pending';
  END IF;
  
  -- Check if requester is owner or admin of the household
  SELECT role INTO v_requester_role
  FROM public.household_members
  WHERE household_id = v_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_requester_role IS NULL OR v_requester_role = 'member' THEN
    RAISE EXCEPTION 'Only owners and admins can reject members';
  END IF;
  
  -- Delete the pending member (rather than marking rejected, to allow re-request)
  DELETE FROM public.household_members
  WHERE id = p_member_id;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- ADD FUNCTION TO FETCH PENDING MEMBERS (for admins/owners)
--------------------------------------------------------------------------------

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
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_requester_role TEXT;
BEGIN
  -- Check if requester is owner or admin of the household
  SELECT hm.role INTO v_requester_role
  FROM public.household_members hm
  WHERE hm.household_id = p_household_id 
    AND hm.user_id = auth.uid() 
    AND hm.status = 'approved';
  
  IF v_requester_role IS NULL OR v_requester_role = 'member' THEN
    RAISE EXCEPTION 'Only owners and admins can view pending members';
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
    hm.updated_at
  FROM public.household_members hm
  WHERE hm.household_id = p_household_id AND hm.status = 'pending'
  ORDER BY hm.created_at;
END;
$$;

--------------------------------------------------------------------------------
-- ADD FUNCTION TO CHECK USER'S PENDING STATUS
-- Allows users to see their own pending membership
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_my_pending_households()
RETURNS TABLE(
  household_id UUID,
  household_name TEXT,
  member_id UUID,
  display_name TEXT,
  status TEXT,
  requested_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    h.id AS household_id,
    h.name AS household_name,
    hm.id AS member_id,
    hm.display_name,
    hm.status,
    hm.created_at AS requested_at
  FROM public.household_members hm
  JOIN public.households h ON h.id = hm.household_id
  WHERE hm.user_id = auth.uid() AND hm.status = 'pending'
  ORDER BY hm.created_at DESC;
END;
$$;

--------------------------------------------------------------------------------
-- UPDATE RLS POLICIES
-- Allow pending members to see their own membership record
--------------------------------------------------------------------------------

-- Drop and recreate the select policy for household_members
DROP POLICY IF EXISTS "Members can view household members" ON public.household_members;

CREATE POLICY "Members can view household members" ON public.household_members
  FOR SELECT USING (
    -- Approved members can see all members of their households
    household_id IN (SELECT public.user_household_ids())
    OR
    -- Users can always see their own membership records (including pending)
    user_id = auth.uid()
  );

--------------------------------------------------------------------------------
-- Done! Member approval system is now active.
--------------------------------------------------------------------------------

