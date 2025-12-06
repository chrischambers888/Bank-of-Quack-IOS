-- Security Fixes Migration
-- Addresses Supabase Security Advisor errors and warnings:
-- 1. SECURITY DEFINER views → use security_invoker = on
-- 2. Mutable search_path in functions → SET search_path = ''
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- FIX: transactions_view SECURITY DEFINER
-- Recreate with security_invoker = on to respect RLS of querying user
--------------------------------------------------------------------------------

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
  ptm.avatar_url AS paid_to_avatar,
  sm.display_name AS split_member_name
FROM public.transactions t
LEFT JOIN public.categories c ON t.category_id = c.id
LEFT JOIN public.household_members pm ON t.paid_by_member_id = pm.id
LEFT JOIN public.household_members ptm ON t.paid_to_member_id = ptm.id
LEFT JOIN public.household_members sm ON t.split_member_id = sm.id;

--------------------------------------------------------------------------------
-- FIX: member_balances SECURITY DEFINER
-- Recreate with security_invoker = on to respect RLS of querying user
--------------------------------------------------------------------------------

DROP VIEW IF EXISTS public.member_balances;

CREATE VIEW public.member_balances
WITH (security_invoker = on)
AS
WITH split_totals AS (
  -- Sum up owed and paid amounts from transaction_splits (expenses only)
  SELECT 
    t.household_id,
    ts.member_id,
    SUM(ts.owed_amount) AS total_owed,
    SUM(ts.paid_amount) AS total_paid
  FROM public.transaction_splits ts
  JOIN public.transactions t ON t.id = ts.transaction_id
  WHERE t.transaction_type = 'expense'
  GROUP BY t.household_id, ts.member_id
),
legacy_expenses AS (
  -- Handle transactions without splits (legacy data)
  -- Now includes both approved and inactive members for historical accuracy
  SELECT
    t.household_id,
    hm.id AS member_id,
    SUM(
      CASE 
        WHEN t.split_type = 'equal' AND NOT EXISTS (
          SELECT 1 FROM public.transaction_splits ts WHERE ts.transaction_id = t.id
        ) THEN t.amount / GREATEST(
          (SELECT COUNT(*) FROM public.household_members WHERE household_id = t.household_id AND status IN ('approved', 'inactive')), 1
        )
        WHEN t.split_type = 'payer_only' AND t.paid_by_member_id = hm.id AND NOT EXISTS (
          SELECT 1 FROM public.transaction_splits ts WHERE ts.transaction_id = t.id
        ) THEN t.amount
        WHEN t.split_type = 'member_only' AND t.split_member_id = hm.id AND NOT EXISTS (
          SELECT 1 FROM public.transaction_splits ts WHERE ts.transaction_id = t.id
        ) THEN t.amount
        ELSE 0
      END
    ) AS legacy_owed,
    SUM(
      CASE 
        WHEN t.paid_by_member_id = hm.id AND NOT EXISTS (
          SELECT 1 FROM public.transaction_splits ts WHERE ts.transaction_id = t.id
        ) THEN t.amount
        ELSE 0
      END
    ) AS legacy_paid
  FROM public.transactions t
  CROSS JOIN public.household_members hm
  WHERE t.household_id = hm.household_id
    AND t.transaction_type = 'expense'
    AND hm.status IN ('approved', 'inactive')
  GROUP BY t.household_id, hm.id
),
settlement_paid AS (
  -- Amount paid by each member in settlements
  SELECT
    household_id,
    paid_by_member_id AS member_id,
    SUM(amount) AS amount_paid
  FROM public.transactions
  WHERE transaction_type = 'settlement'
    AND paid_by_member_id IS NOT NULL
  GROUP BY household_id, paid_by_member_id
),
settlement_received AS (
  -- Amount received by each member in settlements
  SELECT
    household_id,
    paid_to_member_id AS member_id,
    SUM(amount) AS amount_received
  FROM public.transactions
  WHERE transaction_type = 'settlement'
    AND paid_to_member_id IS NOT NULL
  GROUP BY household_id, paid_to_member_id
),
-- For linked reimbursements: calculate the balance impact
-- When someone receives a reimbursement, their out-of-pocket expense is reduced
-- The owed amounts are also reduced proportionally based on original expense splits
linked_reimbursement_paid AS (
  -- The person who received the reimbursement has their effective "paid" amount reduced
  SELECT
    r.household_id,
    r.paid_by_member_id AS member_id,  -- paid_by_member_id stores who received the reimbursement
    SUM(r.amount) AS reimbursement_received
  FROM public.transactions r
  WHERE r.transaction_type = 'reimbursement'
    AND r.reimburses_transaction_id IS NOT NULL
    AND r.paid_by_member_id IS NOT NULL
  GROUP BY r.household_id, r.paid_by_member_id
),
linked_reimbursement_owed AS (
  -- Calculate the "owed" reduction for each member based on original expense split proportions
  -- This reduces what each member owed from the original expense
  SELECT
    e.household_id,
    ts.member_id,
    SUM(
      r.amount * (ts.owed_percentage / 100.0)
    ) AS owed_reduction
  FROM public.transactions r
  JOIN public.transactions e ON e.id = r.reimburses_transaction_id
  JOIN public.transaction_splits ts ON ts.transaction_id = e.id
  WHERE r.transaction_type = 'reimbursement'
    AND r.reimburses_transaction_id IS NOT NULL
  GROUP BY e.household_id, ts.member_id
)
SELECT 
  hm.household_id,
  hm.id AS member_id,
  hm.display_name,
  -- Total paid = expense payments + settlement payments - reimbursements received (reimbursement reduces out-of-pocket)
  COALESCE(st.total_paid, 0) + COALESCE(le.legacy_paid, 0) + COALESCE(sp.amount_paid, 0) - COALESCE(lrp.reimbursement_received, 0) AS total_paid,
  -- Total share/owed = expense share + settlements received - reimbursement owed reductions
  COALESCE(st.total_owed, 0) + COALESCE(le.legacy_owed, 0) + COALESCE(sr.amount_received, 0) - COALESCE(lro.owed_reduction, 0) AS total_share,
  -- Balance = total_paid - total_share
  (COALESCE(st.total_paid, 0) + COALESCE(le.legacy_paid, 0) + COALESCE(sp.amount_paid, 0) - COALESCE(lrp.reimbursement_received, 0)) - 
  (COALESCE(st.total_owed, 0) + COALESCE(le.legacy_owed, 0) + COALESCE(sr.amount_received, 0) - COALESCE(lro.owed_reduction, 0)) AS balance
FROM public.household_members hm
LEFT JOIN split_totals st ON st.member_id = hm.id AND st.household_id = hm.household_id
LEFT JOIN legacy_expenses le ON le.member_id = hm.id AND le.household_id = hm.household_id
LEFT JOIN settlement_paid sp ON sp.member_id = hm.id AND sp.household_id = hm.household_id
LEFT JOIN settlement_received sr ON sr.member_id = hm.id AND sr.household_id = hm.household_id
LEFT JOIN linked_reimbursement_paid lrp ON lrp.member_id = hm.id AND lrp.household_id = hm.household_id
LEFT JOIN linked_reimbursement_owed lro ON lro.member_id = hm.id AND lro.household_id = hm.household_id
WHERE hm.status IN ('approved', 'inactive');

--------------------------------------------------------------------------------
-- FIX: create_transaction_with_splits search_path
-- Add SET search_path = '' to prevent search_path injection attacks
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
-- FIX: update_transaction_with_splits search_path
-- Add SET search_path = '' to prevent search_path injection attacks
--------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.update_transaction_with_splits(UUID, DATE, TEXT, NUMERIC, TEXT, UUID, UUID, UUID, TEXT, TEXT, UUID, UUID, BOOLEAN, TEXT, JSONB);

CREATE OR REPLACE FUNCTION public.update_transaction_with_splits(
  p_transaction_id UUID,
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
  p_splits JSONB DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id UUID;
  v_split JSONB;
  v_member_count INT;
  v_equal_share NUMERIC;
  v_member RECORD;
BEGIN
  -- Get household_id and verify transaction exists
  SELECT household_id INTO v_household_id
  FROM public.transactions
  WHERE id = p_transaction_id;
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Transaction not found';
  END IF;
  
  -- Verify user has access to this household
  IF NOT EXISTS (
    SELECT 1 FROM public.household_members 
    WHERE household_id = v_household_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Update the transaction
  UPDATE public.transactions SET
    date = p_date,
    description = p_description,
    amount = p_amount,
    transaction_type = p_transaction_type,
    paid_by_member_id = p_paid_by_member_id,
    paid_to_member_id = p_paid_to_member_id,
    category_id = p_category_id,
    split_type = p_split_type,
    paid_by_type = p_paid_by_type,
    split_member_id = p_split_member_id,
    reimburses_transaction_id = p_reimburses_transaction_id,
    excluded_from_budget = p_excluded_from_budget,
    notes = p_notes,
    updated_at = NOW()
  WHERE id = p_transaction_id;

  -- Delete existing splits
  DELETE FROM public.transaction_splits WHERE transaction_id = p_transaction_id;

  -- Only create splits for expenses
  IF p_transaction_type = 'expense' THEN
    IF p_splits IS NOT NULL AND jsonb_array_length(p_splits) > 0 THEN
      FOR v_split IN SELECT * FROM jsonb_array_elements(p_splits)
      LOOP
        INSERT INTO public.transaction_splits (
          transaction_id, member_id, amount, percentage, 
          owed_amount, owed_percentage, paid_amount, paid_percentage
        )
        VALUES (
          p_transaction_id,
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
      SELECT COUNT(*) INTO v_member_count
      FROM public.household_members
      WHERE household_id = v_household_id AND status = 'approved';
      
      v_equal_share := p_amount / GREATEST(v_member_count, 1);
      
      FOR v_member IN 
        SELECT id FROM public.household_members 
        WHERE household_id = v_household_id AND status = 'approved'
      LOOP
        INSERT INTO public.transaction_splits (
          transaction_id, member_id, amount, owed_amount, owed_percentage, paid_amount, paid_percentage
        )
        VALUES (
          p_transaction_id,
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
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- Done! Security fixes applied.
-- 
-- MANUAL STEP REQUIRED:
-- Enable "Leaked Password Protection" in Supabase Dashboard:
-- 1. Go to Authentication > Providers > Email
-- 2. Enable "Leaked password protection"
--------------------------------------------------------------------------------
