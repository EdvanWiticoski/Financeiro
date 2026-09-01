-- ============================================================================
-- MIGRAÇÃO: FUNÇÃO SECURITY DEFINER EXCLUIR_MINHA_CONTA (LGPD)
-- Finanças Duo - Direito ao Esquecimento & Exclusão Segura de Dados Pessoais
-- ============================================================================

CREATE OR REPLACE FUNCTION public.excluir_minha_conta()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_fam RECORD;
    v_member_count INT;
    v_deleted_solo_families INT := 0;
    v_left_shared_families INT := 0;
BEGIN
    -- 1. Identifica o usuário logado
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Não autorizado: usuário não autenticado.';
    END IF;

    -- 2. Itera sobre todas as famílias das quais o usuário é membro
    FOR v_fam IN 
        SELECT DISTINCT familia_id 
        FROM public.membros_familia 
        WHERE user_id = v_user_id
    LOOP
        -- Conta quantos membros existem nessa família
        SELECT COUNT(*) INTO v_member_count
        FROM public.membros_familia
        WHERE familia_id = v_fam.familia_id;

        IF v_member_count <= 1 THEN
            -- Usuário é o único membro: Exclui toda a base financeira da família solo
            DELETE FROM public.postings 
            WHERE transaction_id IN (
                SELECT id FROM public.transactions WHERE familia_id = v_fam.familia_id
            );
            
            DELETE FROM public.transactions WHERE familia_id = v_fam.familia_id;
            DELETE FROM public.budgets WHERE familia_id = v_fam.familia_id;
            DELETE FROM public.recurring_patterns WHERE familia_id = v_fam.familia_id;
            DELETE FROM public.investment_valuations WHERE familia_id = v_fam.familia_id;
            DELETE FROM public.accounts WHERE familia_id = v_fam.familia_id;
            DELETE FROM public.membros_familia WHERE familia_id = v_fam.familia_id;
            DELETE FROM public.familias WHERE id = v_fam.familia_id;

            v_deleted_solo_families := v_deleted_solo_families + 1;
        ELSE
            -- Família compartilhada (mais de 1 membro): Remove apenas o vínculo do usuário
            DELETE FROM public.membros_familia 
            WHERE familia_id = v_fam.familia_id AND user_id = v_user_id;

            -- Se o usuário era o único admin da família, promove outro membro a admin
            IF NOT EXISTS (
                SELECT 1 FROM public.membros_familia 
                WHERE familia_id = v_fam.familia_id AND papel = 'admin'
            ) THEN
                UPDATE public.membros_familia
                SET papel = 'admin'
                WHERE ctid IN (
                    SELECT ctid FROM public.membros_familia
                    WHERE familia_id = v_fam.familia_id
                    LIMIT 1
                );
            END IF;

            v_left_shared_families := v_left_shared_families + 1;
        END IF;
    END LOOP;

    -- 3. Exclui preferências e dados pessoais do usuário
    DELETE FROM public.user_settings WHERE user_id = v_user_id;
    DELETE FROM public.usuarios WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Conta e dados pessoais excluídos com sucesso.',
        'solo_families_deleted', v_deleted_solo_families,
        'shared_families_left', v_left_shared_families
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.excluir_minha_conta() TO authenticated;
