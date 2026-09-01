-- ============================================================================
-- MIGRAÇÃO: SISTEMA DE CONVITES DE FAMÍLIA (gerar_convite e aceitar_convite)
-- ============================================================================

-- 1. Recria a tabela de convites de família de forma limpa
DROP TABLE IF EXISTS public.convites_familia CASCADE;

CREATE TABLE public.convites_familia (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    familia_id UUID NOT NULL REFERENCES public.familias(id) ON DELETE CASCADE,
    codigo TEXT NOT NULL UNIQUE,
    criado_por UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    email_convidado TEXT,
    usado BOOLEAN NOT NULL DEFAULT false,
    usado_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '7 days')
);

-- Índices de performance
CREATE INDEX idx_convites_codigo ON public.convites_familia(codigo);
CREATE INDEX idx_convites_familia_id ON public.convites_familia(familia_id);

-- Ativa RLS
ALTER TABLE public.convites_familia ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "convites_select" ON public.convites_familia;
CREATE POLICY "convites_select" ON public.convites_familia FOR SELECT TO authenticated
USING (
    familia_id IN (SELECT public.get_minhas_familias())
    OR criado_por = auth.uid()
);

-- 2. Função RPC para Gerar Código de Convite
CREATE OR REPLACE FUNCTION public.gerar_convite_familia(
    p_familia_id UUID,
    p_email_convidado TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_codigo TEXT;
    v_is_member BOOLEAN;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Usuário não autenticado.';
    END IF;

    -- Verifica se o usuário é membro da família
    SELECT EXISTS (
        SELECT 1 FROM public.membros_familia 
        WHERE familia_id = p_familia_id AND user_id = v_user_id
    ) INTO v_is_member;

    IF NOT v_is_member THEN
        RAISE EXCEPTION 'Apenas membros da família podem gerar convites.';
    END IF;

    -- Gera código de convite único com prefixo DUO-
    v_codigo := 'DUO-' || UPPER(SUBSTRING(MD5(gen_random_uuid()::TEXT || clock_timestamp()::TEXT) FROM 1 FOR 6));

    INSERT INTO public.convites_familia (
        familia_id,
        codigo,
        criado_por,
        email_convidado,
        usado,
        expires_at
    )
    VALUES (
        p_familia_id,
        v_codigo,
        v_user_id,
        NULLIF(TRIM(p_email_convidado), ''),
        false,
        now() + INTERVAL '7 days'
    );

    RETURN v_codigo;
END;
$$;

GRANT EXECUTE ON FUNCTION public.gerar_convite_familia(UUID, TEXT) TO authenticated;

-- 3. Função RPC para Aceitar Convite de Família
CREATE OR REPLACE FUNCTION public.aceitar_convite_familia(
    p_codigo_convite TEXT,
    p_nome_exibicao TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_user_email TEXT;
    v_user_nome TEXT;
    v_convite RECORD;
    v_fam_nome TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Usuário não autenticado.';
    END IF;

    SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;

    -- Localiza o convite ativo e válido
    SELECT * INTO v_convite 
    FROM public.convites_familia
    WHERE codigo = UPPER(TRIM(p_codigo_convite))
      AND usado = false
      AND expires_at > now()
    LIMIT 1;

    IF v_convite IS NULL THEN
        RAISE EXCEPTION 'Código de convite inválido ou expirado.';
    END IF;

    -- Se o convite foi emitido para um e-mail específico, valida
    IF v_convite.email_convidado IS NOT NULL AND v_convite.email_convidado <> '' THEN
        IF v_user_email NOT ILIKE v_convite.email_convidado THEN
            RAISE EXCEPTION 'Este convite foi gerado exclusivamente para o e-mail %.', v_convite.email_convidado;
        END IF;
    END IF;

    -- Busca nome da família
    SELECT nome INTO v_fam_nome FROM public.familias WHERE id = v_convite.familia_id;

    -- Determina o nome de exibição
    v_user_nome := COALESCE(
        NULLIF(TRIM(p_nome_exibicao), ''),
        (SELECT nome FROM public.usuarios WHERE id = v_user_id),
        INITCAP(SPLIT_PART(v_user_email, '@', 1)),
        'Membro'
    );

    -- Insere ou atualiza vínculo do membro na família
    INSERT INTO public.membros_familia (familia_id, user_id, papel, nome_exibicao)
    VALUES (v_convite.familia_id, v_user_id, 'membro', v_user_nome)
    ON CONFLICT (familia_id, user_id) DO UPDATE 
    SET nome_exibicao = EXCLUDED.nome_exibicao;

    -- Atualiza preferências ativas do usuário para a nova família
    INSERT INTO public.user_settings (user_id, familia_id, owner_name, partner_name, onboarding_completed)
    VALUES (v_user_id, v_convite.familia_id, v_user_nome, '', true)
    ON CONFLICT (user_id) DO UPDATE 
    SET familia_id = v_convite.familia_id,
        owner_name = COALESCE(NULLIF(public.user_settings.owner_name, ''), v_user_nome),
        onboarding_completed = true;

    -- Marca convite como utilizado
    UPDATE public.convites_familia
    SET usado = true,
        usado_por = v_user_id
    WHERE id = v_convite.id;

    RETURN jsonb_build_object(
        'success', true,
        'familia_id', v_convite.familia_id,
        'familia_nome', v_fam_nome,
        'message', format('Você entrou na família %s com sucesso!', COALESCE(v_fam_nome, ''))
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.aceitar_convite_familia(TEXT, TEXT) TO authenticated;
