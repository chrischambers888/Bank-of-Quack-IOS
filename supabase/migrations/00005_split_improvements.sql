-- Split Improvements Migration
-- Fixes balance calculations by tracking member snapshots at transaction time
-- Adds support for multi-payer scenarios and "member only" splits
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- UPDATE transaction_splits TABLE
-- Add columns to track who paid and how much
--------------------------------------------------------------------------------

ALTER TABLE public.transaction_splits 
  ADD COLUMN IF NOT EXISTS paid_amount NUMERIC NOT NULL DEFAULT 0 CHECK (paid_amount >= 0);

ALTER TABLE public.transaction_splits 
  ADD COLUMN IF NOT EXISTS paid_percentage NUMERIC;

-- Rename 'amount' to 'owed_amount' for clarity (keeping 'amount' as alias)
-- We'll add a new column and migrate data
ALTER TABLE public.transaction_splits 
  ADD COLUMN IF NOT EXISTS owed_amount NUMERIC NOT NULL DEFAULT 0 CHECK (owed_amount >= 0);

ALTER TABLE public.transaction_splits 
  ADD COLUMN IF NOT EXISTS owed_percentage NUMERIC;

-- Migrate existing data from 'amount' to 'owed_amount'
UPDATE public.transaction_splits 
SET owed_amount = amount, owed_percentage = percentage
WHERE owed_amount = 0 AND amount > 0;

--------------------------------------------------------------------------------
-- UPDATE transactions TABLE
-- Add new split types and paid_by options
--------------------------------------------------------------------------------

-- Drop existing constraint on split_type
ALTER TABLE public.transactions 
  DROP CONSTRAINT IF EXISTS transactions_split_type_check;

-- Add updated constraint with 'member_only' option
ALTER TABLE public.transactions 
  ADD CONSTRAINT transactions_split_type_check 
  CHECK (split_type IN ('equal', 'custom', 'payer_only', 'member_only'));

-- Add paid_by_type column for tracking how payment was split
ALTER TABLE public.transactions 
  ADD COLUMN IF NOT EXISTS paid_by_type TEXT NOT NULL DEFAULT 'single' 
  CHECK (paid_by_type IN ('single', 'shared', 'custom'));

-- Add column to track which member bears the cost for 'member_only' split type
ALTER TABLE public.transactions 
  ADD COLUMN IF NOT EXISTS split_member_id UUID REFERENCES public.household_members(id) ON DELETE SET NULL;

--------------------------------------------------------------------------------
-- UPDATE member_balances VIEW
-- Calculate from transaction_splits instead of dividing by member count
--------------------------------------------------------------------------------

DROP VIEW IF EXISTS public.member_balances;

CREATE OR REPLACE VIEW public.member_balances AS
WITH split_totals AS (
  -- Sum up owed and paid amounts from transaction_splits
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
  -- For equal splits without transaction_splits records
  SELECT
    t.household_id,
    hm.id AS member_id,
    SUM(
      CASE 
        WHEN t.split_type = 'equal' AND NOT EXISTS (
          SELECT 1 FROM public.transaction_splits ts WHERE ts.transaction_id = t.id
        ) THEN t.amount / GREATEST(
          (SELECT COUNT(*) FROM public.household_members WHERE household_id = t.household_id AND status = 'approved'), 1
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
    AND hm.status = 'approved'
  GROUP BY t.household_id, hm.id
),
settlements AS (
  -- Track settlements between members
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
  COALESCE(st.total_paid, 0) + COALESCE(le.legacy_paid, 0) AS total_paid,
  COALESCE(st.total_owed, 0) + COALESCE(le.legacy_owed, 0) AS total_share,
  (COALESCE(st.total_paid, 0) + COALESCE(le.legacy_paid, 0)) - 
  (COALESCE(st.total_owed, 0) + COALESCE(le.legacy_owed, 0)) AS balance
FROM public.household_members hm
LEFT JOIN split_totals st ON st.member_id = hm.id AND st.household_id = hm.household_id
LEFT JOIN legacy_expenses le ON le.member_id = hm.id AND le.household_id = hm.household_id
WHERE hm.status = 'approved';

--------------------------------------------------------------------------------
-- UPDATE transactions_view to include new columns
--------------------------------------------------------------------------------

DROP VIEW IF EXISTS public.transactions_view;

CREATE OR REPLACE VIEW public.transactions_view AS
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
-- HELPER FUNCTION: Create splits for a transaction
--------------------------------------------------------------------------------

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
  p_excluded_from_budget BOOLEAN,
  p_notes TEXT,
  p_created_by_user_id UUID,
  p_splits JSONB DEFAULT NULL -- Array of {member_id, owed_amount, owed_percentage, paid_amount, paid_percentage}
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
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
    paid_by_type, split_member_id, excluded_from_budget, notes, created_by_user_id
  )
  VALUES (
    p_household_id, p_date, p_description, p_amount, p_transaction_type,
    p_paid_by_member_id, p_paid_to_member_id, p_category_id, p_split_type,
    p_paid_by_type, p_split_member_id, p_excluded_from_budget, p_notes, p_created_by_user_id
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
      
      -- Get approved members count
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
          -- owed_amount (legacy 'amount' column)
          CASE 
            WHEN p_split_type = 'equal' THEN v_equal_share
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN p_amount
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN p_amount
            ELSE 0
          END,
          -- owed_amount
          CASE 
            WHEN p_split_type = 'equal' THEN v_equal_share
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN p_amount
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN p_amount
            ELSE 0
          END,
          -- owed_percentage
          CASE 
            WHEN p_split_type = 'equal' THEN 100.0 / v_member_count
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN 100
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN 100
            ELSE 0
          END,
          -- paid_amount
          CASE 
            WHEN p_paid_by_type = 'single' AND v_member.id = p_paid_by_member_id THEN p_amount
            WHEN p_paid_by_type = 'shared' THEN v_equal_share
            ELSE 0
          END,
          -- paid_percentage
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
-- HELPER FUNCTION: Update a transaction with splits
--------------------------------------------------------------------------------

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
  p_excluded_from_budget BOOLEAN,
  p_notes TEXT,
  p_splits JSONB DEFAULT NULL -- Array of {member_id, owed_amount, owed_percentage, paid_amount, paid_percentage}
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
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
    excluded_from_budget = p_excluded_from_budget,
    notes = p_notes,
    updated_at = NOW()
  WHERE id = p_transaction_id;

  -- Delete existing splits
  DELETE FROM public.transaction_splits WHERE transaction_id = p_transaction_id;

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
      -- Auto-generate splits based on split_type and paid_by_type
      
      -- Get approved members count
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
          -- owed_amount (legacy 'amount' column)
          CASE 
            WHEN p_split_type = 'equal' THEN v_equal_share
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN p_amount
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN p_amount
            ELSE 0
          END,
          -- owed_amount
          CASE 
            WHEN p_split_type = 'equal' THEN v_equal_share
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN p_amount
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN p_amount
            ELSE 0
          END,
          -- owed_percentage
          CASE 
            WHEN p_split_type = 'equal' THEN 100.0 / v_member_count
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN 100
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN 100
            ELSE 0
          END,
          -- paid_amount
          CASE 
            WHEN p_paid_by_type = 'single' AND v_member.id = p_paid_by_member_id THEN p_amount
            WHEN p_paid_by_type = 'shared' THEN v_equal_share
            ELSE 0
          END,
          -- paid_percentage
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

