-- ============================================================================
-- MIGRAÇÃO: VALIDAÇÃO DE PARTIDAS DOBRADAS (BALANCE CHECK TRIGGER)
-- Finanças Duo - Integridade Contábil Rigorosa no Banco de Dados
-- Impede que qualquer transação seja gravada ou alterada com soma <> 0
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_transaction_balance()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE 
    v_sum NUMERIC;
BEGIN
    SELECT COALESCE(SUM(amount), 0) INTO v_sum
    FROM public.postings 
    WHERE transaction_id = COALESCE(NEW.transaction_id, OLD.transaction_id);

    IF ROUND(v_sum, 2) <> 0 THEN
        RAISE EXCEPTION 'Lançamento desbalanceado: soma dos débitos e créditos = % (deve ser 0)', v_sum;
    END IF;

    RETURN NEW;
END; 
$$;

DROP TRIGGER IF EXISTS trg_check_balance ON public.postings;

CREATE CONSTRAINT TRIGGER trg_check_balance
AFTER INSERT OR UPDATE OR DELETE ON public.postings
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.check_transaction_balance();
