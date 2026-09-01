-- ============================================================================
-- MIGRAÇÃO DE SEGURANÇA: RLS ESTRITO NA TABELA PUBLIC.USUARIOS
-- Impede vazamento de dados cadastrais (telefone, e-mail, foto, endereço)
-- Usuário só enxerga a si próprio ou quem pertence à mesma família
-- ============================================================================

DROP POLICY IF EXISTS "usuarios_select" ON public.usuarios;

CREATE POLICY "usuarios_select" ON public.usuarios FOR SELECT TO authenticated
USING (
    id = auth.uid()
    OR id IN (
        SELECT mf2.user_id 
        FROM public.membros_familia mf1
        JOIN public.membros_familia mf2 ON mf2.familia_id = mf1.familia_id
        WHERE mf1.user_id = auth.uid()
    )
);
