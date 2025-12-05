-- Settlement Balance Fix Migration
-- Fixes the member_balances view to properly incorporate settlements
-- Settlements transfer balance from one member to another
--------------------------------------------------------------------------------

DROP VIEW IF EXISTS public.member_balances;

CREATE OR REPLACE VIEW public.member_balances AS
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
settlement_paid AS (
  -- Amount paid by each member in settlements (reduces their balance - they paid to settle up)
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
  -- Amount received by each member in settlements (increases their balance - they received payment)
  SELECT
    household_id,
    paid_to_member_id AS member_id,
    SUM(amount) AS amount_received
  FROM public.transactions
  WHERE transaction_type = 'settlement'
    AND paid_to_member_id IS NOT NULL
  GROUP BY household_id, paid_to_member_id
)
SELECT 
  hm.household_id,
  hm.id AS member_id,
  hm.display_name,
  -- Total paid = expense payments + settlement payments made
  COALESCE(st.total_paid, 0) + COALESCE(le.legacy_paid, 0) + COALESCE(sp.amount_paid, 0) AS total_paid,
  -- Total share/owed = expense share + settlements received (money received is like owing more)
  COALESCE(st.total_owed, 0) + COALESCE(le.legacy_owed, 0) + COALESCE(sr.amount_received, 0) AS total_share,
  -- Balance = (expense paid + settlements paid) - (expense owed + settlements received)
  (COALESCE(st.total_paid, 0) + COALESCE(le.legacy_paid, 0) + COALESCE(sp.amount_paid, 0)) - 
  (COALESCE(st.total_owed, 0) + COALESCE(le.legacy_owed, 0) + COALESCE(sr.amount_received, 0)) AS balance
FROM public.household_members hm
LEFT JOIN split_totals st ON st.member_id = hm.id AND st.household_id = hm.household_id
LEFT JOIN legacy_expenses le ON le.member_id = hm.id AND le.household_id = hm.household_id
LEFT JOIN settlement_paid sp ON sp.member_id = hm.id AND sp.household_id = hm.household_id
LEFT JOIN settlement_received sr ON sr.member_id = hm.id AND sr.household_id = hm.household_id
WHERE hm.status = 'approved';



