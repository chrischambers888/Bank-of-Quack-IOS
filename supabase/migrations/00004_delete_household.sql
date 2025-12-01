-- Quack App - Delete Household Function
-- Allows owners to permanently delete a household and all associated data
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- ADD FUNCTION TO DELETE HOUSEHOLD (owner only)
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.delete_household(p_household_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_requester_role TEXT;
BEGIN
  -- Check if requester is owner of the household
  SELECT role INTO v_requester_role
  FROM public.household_members
  WHERE household_id = p_household_id 
    AND user_id = auth.uid() 
    AND status = 'approved';
  
  IF v_requester_role IS NULL OR v_requester_role != 'owner' THEN
    RAISE EXCEPTION 'Only the owner can delete a household';
  END IF;
  
  -- Delete the household (CASCADE will handle all related data)
  -- This will delete: members, transactions, categories, sectors, budgets, etc.
  DELETE FROM public.households
  WHERE id = p_household_id;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- Done! Household deletion is now available for owners.
--------------------------------------------------------------------------------

