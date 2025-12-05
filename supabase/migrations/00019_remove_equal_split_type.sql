-- Remove Dynamic Equal Split Type Migration
-- Converts all 'equal' and 'shared' splits to explicit 'custom' splits
-- This ensures balance calculations remain accurate as household membership changes
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- STEP 1: Generate explicit splits for transactions with 'equal' split_type
-- that don't already have transaction_splits rows
--------------------------------------------------------------------------------

-- Insert splits for transactions with split_type = 'equal' and no existing splits
INSERT INTO public.transaction_splits (
  transaction_id, member_id, amount, percentage,
  owed_amount, owed_percentage, paid_amount, paid_percentage
)
SELECT 
  t.id AS transaction_id,
  hm.id AS member_id,
  t.amount / member_counts.cnt AS amount,
  100.0 / member_counts.cnt AS percentage,
  t.amount / member_counts.cnt AS owed_amount,
  100.0 / member_counts.cnt AS owed_percentage,
  CASE 
    WHEN t.paid_by_type = 'single' AND hm.id = t.paid_by_member_id THEN t.amount
    WHEN t.paid_by_type = 'shared' THEN t.amount / member_counts.cnt
    ELSE 0
  END AS paid_amount,
  CASE 
    WHEN t.paid_by_type = 'single' AND hm.id = t.paid_by_member_id THEN 100
    WHEN t.paid_by_type = 'shared' THEN 100.0 / member_counts.cnt
    ELSE 0
  END AS paid_percentage
FROM public.transactions t
CROSS JOIN public.household_members hm
CROSS JOIN LATERAL (
  SELECT COUNT(*) AS cnt 
  FROM public.household_members 
  WHERE household_id = t.household_id 
    AND status IN ('approved', 'inactive')
) member_counts
WHERE t.transaction_type = 'expense'
  AND t.split_type = 'equal'
  AND t.household_id = hm.household_id
  AND hm.status IN ('approved', 'inactive')
  AND NOT EXISTS (
    SELECT 1 FROM public.transaction_splits ts WHERE ts.transaction_id = t.id
  )
ON CONFLICT (transaction_id, member_id) DO NOTHING;

--------------------------------------------------------------------------------
-- STEP 2: Update paid_amount for transactions with 'shared' paid_by_type
-- that already have splits but may not have correct paid_amount values
--------------------------------------------------------------------------------

UPDATE public.transaction_splits ts
SET 
  paid_amount = t.amount / member_counts.cnt,
  paid_percentage = 100.0 / member_counts.cnt
FROM public.transactions t
CROSS JOIN LATERAL (
  SELECT COUNT(*) AS cnt 
  FROM public.transaction_splits 
  WHERE transaction_id = t.id
) member_counts
WHERE ts.transaction_id = t.id
  AND t.paid_by_type = 'shared'
  AND t.transaction_type = 'expense'
  AND member_counts.cnt > 0;

--------------------------------------------------------------------------------
-- STEP 3: Update all 'equal' split_type to 'custom'
--------------------------------------------------------------------------------

UPDATE public.transactions
SET split_type = 'custom'
WHERE split_type = 'equal';

--------------------------------------------------------------------------------
-- STEP 4: Update all 'shared' paid_by_type to 'custom'
--------------------------------------------------------------------------------

UPDATE public.transactions
SET paid_by_type = 'custom'
WHERE paid_by_type = 'shared';

--------------------------------------------------------------------------------
-- STEP 5: Update transaction_templates to convert 'equal' and 'shared'
--------------------------------------------------------------------------------

UPDATE public.transaction_templates
SET split_type = 'custom'
WHERE split_type = 'equal';

UPDATE public.transaction_templates
SET paid_by_type = 'custom'
WHERE paid_by_type = 'shared';

--------------------------------------------------------------------------------
-- STEP 6: Update constraints on transactions table
-- Remove 'equal' from split_type and 'shared' from paid_by_type
--------------------------------------------------------------------------------

-- Drop existing constraints
ALTER TABLE public.transactions DROP CONSTRAINT IF EXISTS transactions_split_type_check;
ALTER TABLE public.transactions DROP CONSTRAINT IF EXISTS transactions_paid_by_type_check;

-- Add new constraints without 'equal' and 'shared'
ALTER TABLE public.transactions
  ADD CONSTRAINT transactions_split_type_check 
  CHECK (split_type IN ('custom', 'payer_only', 'member_only'));

ALTER TABLE public.transactions
  ADD CONSTRAINT transactions_paid_by_type_check 
  CHECK (paid_by_type IN ('single', 'custom'));

--------------------------------------------------------------------------------
-- STEP 7: Update constraints on transaction_templates table
--------------------------------------------------------------------------------

-- Drop existing constraints  
ALTER TABLE public.transaction_templates DROP CONSTRAINT IF EXISTS transaction_templates_split_type_check;
ALTER TABLE public.transaction_templates DROP CONSTRAINT IF EXISTS transaction_templates_paid_by_type_check;

-- Add new constraints without 'equal' and 'shared'
ALTER TABLE public.transaction_templates
  ADD CONSTRAINT transaction_templates_split_type_check 
  CHECK (split_type IN ('custom', 'payer_only', 'member_only'));

ALTER TABLE public.transaction_templates
  ADD CONSTRAINT transaction_templates_paid_by_type_check 
  CHECK (paid_by_type IN ('single', 'custom'));

--------------------------------------------------------------------------------
-- STEP 8: Simplify member_balances view
-- Remove the legacy_expenses CTE since all transactions now have explicit splits
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
  -- Total paid = expense payments + settlement payments - reimbursements received
  COALESCE(st.total_paid, 0) + COALESCE(sp.amount_paid, 0) - COALESCE(lrp.reimbursement_received, 0) AS total_paid,
  -- Total share/owed = expense share + settlements received - reimbursement owed reductions
  COALESCE(st.total_owed, 0) + COALESCE(sr.amount_received, 0) - COALESCE(lro.owed_reduction, 0) AS total_share,
  -- Balance = total_paid - total_share
  (COALESCE(st.total_paid, 0) + COALESCE(sp.amount_paid, 0) - COALESCE(lrp.reimbursement_received, 0)) - 
  (COALESCE(st.total_owed, 0) + COALESCE(sr.amount_received, 0) - COALESCE(lro.owed_reduction, 0)) AS balance
FROM public.household_members hm
LEFT JOIN split_totals st ON st.member_id = hm.id AND st.household_id = hm.household_id
LEFT JOIN settlement_paid sp ON sp.member_id = hm.id AND sp.household_id = hm.household_id
LEFT JOIN settlement_received sr ON sr.member_id = hm.id AND sr.household_id = hm.household_id
LEFT JOIN linked_reimbursement_paid lrp ON lrp.member_id = hm.id AND lrp.household_id = hm.household_id
LEFT JOIN linked_reimbursement_owed lro ON lro.member_id = hm.id AND lro.household_id = hm.household_id
WHERE hm.status IN ('approved', 'inactive');

--------------------------------------------------------------------------------
-- STEP 9: Update create_transaction_with_splits function
-- Remove special handling for 'equal' and 'shared' since client always sends splits
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
      -- Use provided splits (required for all expense transactions now)
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
      -- Fallback: Auto-generate splits based on split_type and paid_by_type
      -- This is for backwards compatibility with older clients
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
            WHEN p_split_type = 'custom' THEN v_equal_share  -- Default to equal for custom without splits
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN p_amount
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN p_amount
            ELSE 0
          END,
          CASE 
            WHEN p_split_type = 'custom' THEN v_equal_share
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN p_amount
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN p_amount
            ELSE 0
          END,
          CASE 
            WHEN p_split_type = 'custom' THEN 100.0 / v_member_count
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN 100
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN 100
            ELSE 0
          END,
          CASE 
            WHEN p_paid_by_type = 'single' AND v_member.id = p_paid_by_member_id THEN p_amount
            WHEN p_paid_by_type = 'custom' THEN v_equal_share  -- Default to equal for custom without splits
            ELSE 0
          END,
          CASE 
            WHEN p_paid_by_type = 'single' AND v_member.id = p_paid_by_member_id THEN 100
            WHEN p_paid_by_type = 'custom' THEN 100.0 / v_member_count
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
-- STEP 10: Update update_transaction_with_splits function
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
  -- Get the household_id for the transaction
  SELECT household_id INTO v_household_id
  FROM public.transactions
  WHERE id = p_transaction_id;
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Transaction not found';
  END IF;

  -- Update the transaction
  UPDATE public.transactions
  SET
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

  -- Only update splits for expenses
  IF p_transaction_type = 'expense' THEN
    -- Delete existing splits
    DELETE FROM public.transaction_splits WHERE transaction_id = p_transaction_id;
    
    IF p_splits IS NOT NULL AND jsonb_array_length(p_splits) > 0 THEN
      -- Use provided splits
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
      -- Fallback: Auto-generate splits based on split_type and paid_by_type
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
            WHEN p_split_type = 'custom' THEN v_equal_share
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN p_amount
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN p_amount
            ELSE 0
          END,
          CASE 
            WHEN p_split_type = 'custom' THEN v_equal_share
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN p_amount
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN p_amount
            ELSE 0
          END,
          CASE 
            WHEN p_split_type = 'custom' THEN 100.0 / v_member_count
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN 100
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN 100
            ELSE 0
          END,
          CASE 
            WHEN p_paid_by_type = 'single' AND v_member.id = p_paid_by_member_id THEN p_amount
            WHEN p_paid_by_type = 'custom' THEN v_equal_share
            ELSE 0
          END,
          CASE 
            WHEN p_paid_by_type = 'single' AND v_member.id = p_paid_by_member_id THEN 100
            WHEN p_paid_by_type = 'custom' THEN 100.0 / v_member_count
            ELSE 0
          END
        );
      END LOOP;
    END IF;
  ELSE
    -- Non-expense transactions don't have splits
    DELETE FROM public.transaction_splits WHERE transaction_id = p_transaction_id;
  END IF;
  
  RETURN TRUE;
END;
$$;


