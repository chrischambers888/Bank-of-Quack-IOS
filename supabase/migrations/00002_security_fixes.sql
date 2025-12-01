-- Quack App - Security Fixes
-- Addresses Supabase Security Advisor warnings
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- FIX VIEWS: Enable security_invoker so views respect RLS of querying user
--------------------------------------------------------------------------------

-- Recreate transactions_view with security_invoker
DROP VIEW IF EXISTS public.transactions_view;
CREATE VIEW public.transactions_view
WITH (security_invoker = on)
AS
SELECT 
  t.*,
  c.name AS category_name,
  c.icon AS category_icon,
  c.color AS category_color,
  pm.display_name AS paid_by_name,
  pm.avatar_url AS paid_by_avatar,
  ptm.display_name AS paid_to_name,
  ptm.avatar_url AS paid_to_avatar
FROM public.transactions t
LEFT JOIN public.categories c ON t.category_id = c.id
LEFT JOIN public.household_members pm ON t.paid_by_member_id = pm.id
LEFT JOIN public.household_members ptm ON t.paid_to_member_id = ptm.id;

-- Recreate member_balances view with security_invoker
DROP VIEW IF EXISTS public.member_balances;
CREATE VIEW public.member_balances
WITH (security_invoker = on)
AS
WITH member_expenses AS (
  -- What each member has paid
  SELECT 
    t.household_id,
    t.paid_by_member_id AS member_id,
    SUM(CASE 
      WHEN t.transaction_type = 'expense' AND t.split_type = 'equal' THEN t.amount
      WHEN t.transaction_type = 'expense' AND t.split_type = 'payer_only' THEN t.amount
      ELSE 0
    END) AS total_paid
  FROM public.transactions t
  WHERE t.paid_by_member_id IS NOT NULL
  GROUP BY t.household_id, t.paid_by_member_id
),
member_shares AS (
  -- What each member owes (their share of expenses)
  SELECT
    t.household_id,
    hm.id AS member_id,
    SUM(
      CASE 
        WHEN t.split_type = 'equal' THEN t.amount / member_count.cnt
        WHEN t.split_type = 'payer_only' AND t.paid_by_member_id = hm.id THEN t.amount
        WHEN t.split_type = 'custom' THEN COALESCE(ts.amount, 0)
        ELSE 0
      END
    ) AS total_share
  FROM public.transactions t
  CROSS JOIN public.household_members hm
  LEFT JOIN public.transaction_splits ts ON ts.transaction_id = t.id AND ts.member_id = hm.id
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt 
    FROM public.household_members 
    WHERE household_id = t.household_id
  ) member_count ON TRUE
  WHERE t.household_id = hm.household_id
    AND t.transaction_type = 'expense'
  GROUP BY t.household_id, hm.id
),
settlements AS (
  SELECT
    household_id,
    paid_by_member_id AS from_member_id,
    paid_to_member_id AS to_member_id,
    SUM(amount) AS settled_amount
  FROM public.transactions
  WHERE transaction_type = 'settlement'
  GROUP BY household_id, paid_by_member_id, paid_to_member_id
)
SELECT 
  hm.household_id,
  hm.id AS member_id,
  hm.display_name,
  COALESCE(me.total_paid, 0) AS total_paid,
  COALESCE(ms.total_share, 0) AS total_share,
  COALESCE(me.total_paid, 0) - COALESCE(ms.total_share, 0) AS balance
FROM public.household_members hm
LEFT JOIN member_expenses me ON me.member_id = hm.id
LEFT JOIN member_shares ms ON ms.member_id = hm.id;

--------------------------------------------------------------------------------
-- FIX FUNCTIONS: Set immutable search_path to prevent injection attacks
--------------------------------------------------------------------------------

-- Fix user_household_ids function
CREATE OR REPLACE FUNCTION public.user_household_ids()
RETURNS SETOF UUID
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
  SELECT household_id FROM public.household_members WHERE user_id = auth.uid();
$$;

-- Fix create_household function
CREATE OR REPLACE FUNCTION public.create_household(
  p_name TEXT,
  p_display_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id UUID;
BEGIN
  -- Create household
  INSERT INTO public.households (name)
  VALUES (p_name)
  RETURNING id INTO v_household_id;
  
  -- Add creator as owner
  INSERT INTO public.household_members (household_id, user_id, display_name, role)
  VALUES (v_household_id, auth.uid(), p_display_name, 'owner');
  
  RETURN v_household_id;
END;
$$;

-- Fix join_household function
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
BEGIN
  -- Find household by invite code
  SELECT id INTO v_household_id
  FROM public.households
  WHERE invite_code = p_invite_code;
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Invalid invite code';
  END IF;
  
  -- Check if already a member
  IF EXISTS (
    SELECT 1 FROM public.household_members 
    WHERE household_id = v_household_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Already a member of this household';
  END IF;
  
  -- Add as member
  INSERT INTO public.household_members (household_id, user_id, display_name, role)
  VALUES (v_household_id, auth.uid(), p_display_name, 'member');
  
  RETURN v_household_id;
END;
$$;

-- Fix regenerate_invite_code function
CREATE OR REPLACE FUNCTION public.regenerate_invite_code(p_household_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_new_code TEXT;
BEGIN
  -- Verify user is owner
  IF NOT EXISTS (
    SELECT 1 FROM public.household_members 
    WHERE household_id = p_household_id 
      AND user_id = auth.uid() 
      AND role = 'owner'
  ) THEN
    RAISE EXCEPTION 'Only owners can regenerate invite codes';
  END IF;
  
  v_new_code := encode(gen_random_bytes(6), 'hex');
  
  UPDATE public.households
  SET invite_code = v_new_code, updated_at = NOW()
  WHERE id = p_household_id;
  
  RETURN v_new_code;
END;
$$;

-- Fix update_updated_at trigger function
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

--------------------------------------------------------------------------------
-- Done! All security issues addressed.
--------------------------------------------------------------------------------



