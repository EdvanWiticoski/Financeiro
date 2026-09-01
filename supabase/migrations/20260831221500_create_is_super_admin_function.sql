-- ============================================================================
-- MIGRAÇÃO: FUNÇÃO SECURITY DEFINER IS_SUPER_ADMIN
-- Permite ao cliente verificar com segurança o papel de Super Admin do usuário logado
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE((SELECT is_super_admin FROM public.usuarios WHERE id = auth.uid()), false);
$$;

GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;
