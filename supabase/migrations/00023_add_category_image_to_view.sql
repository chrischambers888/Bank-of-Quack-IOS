-- Migration: Add category image_url to transactions_view
-- This allows displaying category photos in transaction lists

DROP VIEW IF EXISTS public.transactions_view;

CREATE VIEW public.transactions_view
WITH (security_invoker = on)
AS
SELECT 
  t.*,
  c.name AS category_name,
  c.icon AS category_icon,
  c.color AS category_color,
  c.image_url AS category_image_url,
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
