-- ==============================================================================
-- DOCUMENT SCANNER SEED DATA
-- ==============================================================================

INSERT INTO public.scanned_documents (
    id, file_name, document_type, status,
    document_number, cpf, cpf_valid, full_name,
    birth_date, mother_name, issuing_organ, issuing_state,
    cnh_category, confidence_score
)
VALUES
(
    '11111111-1111-1111-1111-111111111111',
    'rg_mariana_costa.jpg',
    'rg',
    'auto_verified',
    '38.452.190-8',
    '529.982.247-25',
    true,
    'MARIANA RIBEIRO COSTA',
    '18/07/1992',
    'TERESA RIBEIRO COSTA',
    'SSP',
    'SP',
    null,
    0.95
),
(
    '22222222-2222-2222-2222-222222222222',
    'cnh_fabiano_brito.jpg',
    'cnh',
    'auto_verified',
    '00748806880',
    '275.153.968-81',
    true,
    'FABIANO LUIS DE BRITO',
    '19/11/1979',
    'ELMA BRITO DE MOURA',
    'DETRAN',
    'SP',
    'ACC',
    0.96
)
ON CONFLICT (id) DO NOTHING;
