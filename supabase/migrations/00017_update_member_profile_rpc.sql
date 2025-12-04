-- Quack App - Add RPC function for updating member profile
-- This provides a more reliable way to update profile data, bypassing potential RLS issues
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- RPC FUNCTION: update_my_profile
-- Allows a user to update their own member profile in a specific household
--------------------------------------------------------------------------------

-- Drop any existing versions of this function
DROP FUNCTION IF EXISTS public.update_my_profile(TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.update_my_profile(UUID, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.update_my_profile(
  p_member_id UUID,
  p_display_name TEXT DEFAULT NULL,
  p_avatar_url TEXT DEFAULT NULL,
  p_color TEXT DEFAULT NULL
)
RETURNS public.household_members
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_member public.household_members;
BEGIN
  -- Update the member record only if it belongs to the current user
  UPDATE public.household_members
  SET 
    display_name = COALESCE(p_display_name, display_name),
    avatar_url = CASE 
      WHEN p_avatar_url IS NOT NULL THEN p_avatar_url 
      ELSE avatar_url 
    END,
    color = COALESCE(p_color, color),
    updated_at = NOW()
  WHERE id = p_member_id
    AND user_id = auth.uid()  -- Security: only allow updating own profile
  RETURNING * INTO v_member;
  
  -- Check if we actually updated a row
  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Member not found or you do not have permission to update this profile';
  END IF;
  
  RETURN v_member;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.update_my_profile(UUID, TEXT, TEXT, TEXT) TO authenticated;

