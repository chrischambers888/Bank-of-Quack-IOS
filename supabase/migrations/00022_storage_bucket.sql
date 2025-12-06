-- Migration: Create storage bucket for avatar and category images
-- This bucket stores downsized photos for member avatars and category icons

-- Create the avatars storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,  -- Public bucket so images can be displayed without auth
  102400,  -- 100KB limit (our target is ~50KB)
  ARRAY['image/jpeg', 'image/jpg']
)
ON CONFLICT (id) DO NOTHING;

-- RLS Policies for storage.objects

-- Policy: Anyone can view images (public bucket)
CREATE POLICY "Public read access for avatars"
ON storage.objects FOR SELECT
USING (bucket_id = 'avatars');

-- Policy: Authenticated users can upload to their own folder or to folders of households they belong to
-- The path format is: {owner_user_id}/{filename}
CREATE POLICY "Users can upload avatars"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars'
  AND (
    -- User can upload to their own folder
    (storage.foldername(name))[1] = auth.uid()::text
    OR
    -- User can upload to folder of a household owner they belong to
    EXISTS (
      SELECT 1 FROM household_members hm1
      JOIN household_members hm2 ON hm1.household_id = hm2.household_id
      WHERE hm1.user_id = auth.uid()
        AND hm1.status = 'approved'
        AND hm2.role = 'owner'
        AND hm2.user_id::text = (storage.foldername(name))[1]
    )
  )
);

-- Policy: Users can update their own uploads or uploads in their owned households
CREATE POLICY "Users can update avatars"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (
    -- User owns the folder
    (storage.foldername(name))[1] = auth.uid()::text
    OR
    -- User is owner of a household and this is their folder
    EXISTS (
      SELECT 1 FROM household_members hm
      WHERE hm.user_id = auth.uid()
        AND hm.role = 'owner'
        AND hm.user_id::text = (storage.foldername(name))[1]
    )
  )
);

-- Policy: Users can delete from their own folder or if they're household owner
CREATE POLICY "Users can delete avatars"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (
    -- User owns the folder
    (storage.foldername(name))[1] = auth.uid()::text
    OR
    -- User is owner of a household and this is their folder
    EXISTS (
      SELECT 1 FROM household_members hm
      WHERE hm.user_id = auth.uid()
        AND hm.role = 'owner'
        AND hm.user_id::text = (storage.foldername(name))[1]
    )
  )
);
