-- ============================================================================
-- MIGRAÇÃO DE SEGURANÇA: RLS ESTRITO NA TABELA PUBLIC.MEMBROS_FAMILIA
-- Impede auto-inserção com papel "admin" e blindagem contra entrada sem convite
-- ============================================================================

DROP POLICY IF EXISTS "membros_insert" ON public.membros_familia;

CREATE POLICY "membros_insert" ON public.membros_familia FOR INSERT TO authenticated
WITH CHECK (
    (user_id = auth.uid() AND papel = 'membro')
    OR familia_id IN (
        SELECT mf.familia_id 
        FROM public.membros_familia mf 
        WHERE mf.user_id = auth.uid() AND mf.papel = 'admin'
    )
);
