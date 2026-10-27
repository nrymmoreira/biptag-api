--------------------------------------------------------------------------------
-- 1. APP_USERS
--------------------------------------------------------------------------------
INSERT INTO app_users (id, email, full_name, created_at) VALUES
('11111111-1111-1111-1111-111111111111', 'joao.silva@email.com', 'João Silva', SYSTIMESTAMP - 60);
INSERT INTO app_users (id, email, full_name, created_at) VALUES
('22222222-2222-2222-2222-222222222222', 'maria.souza@email.com', 'Maria Souza', SYSTIMESTAMP - 55);
INSERT INTO app_users (id, email, full_name, created_at) VALUES
('33333333-3333-3333-3333-333333333333', 'carlos.pereira@email.com', 'Carlos Pereira', SYSTIMESTAMP - 40);
INSERT INTO app_users (id, email, full_name, created_at) VALUES
('44444444-4444-4444-4444-444444444444', 'ana.lima@email.com', 'Ana Lima', SYSTIMESTAMP - 30);
INSERT INTO app_users (id, email, full_name, created_at) VALUES
('55555555-5555-5555-5555-555555555555', 'pedro.costa@email.com', 'Pedro Costa', SYSTIMESTAMP - 20);

--------------------------------------------------------------------------------
-- 2. CATEGORY
--------------------------------------------------------------------------------
INSERT INTO category (name) VALUES ('Eletrônicos');
INSERT INTO category (name) VALUES ('Documentos');
INSERT INTO category (name) VALUES ('Chaves');
INSERT INTO category (name) VALUES ('Bolsas e Mochilas');
INSERT INTO category (name) VALUES ('Óculos');
INSERT INTO category (name) VALUES ('Outros');

--------------------------------------------------------------------------------
-- 3. PARTNER_POINTS
--------------------------------------------------------------------------------
INSERT INTO partner_points (name, address, latitude, longitude, working_hours) VALUES
('Loja Parceira Centro', 'Rua 10, 123 - Centro, Goiânia - GO', -16.6799, -49.2550, 'Seg-Sex 08h-18h');
INSERT INTO partner_points (name, address, latitude, longitude, working_hours) VALUES
('Ponto Parceiro Setor Bueno', 'Av. T-9, 456 - Setor Bueno, Goiânia - GO', -16.7090, -49.2680, 'Seg-Sáb 09h-20h');
INSERT INTO partner_points (name, address, latitude, longitude, working_hours) VALUES
('Shopping Flamboyant - Quiosque', 'Av. Laudelino Gomes, 1600 - Jardim Goiás, Goiânia - GO', -16.7150, -49.2450, 'Todos os dias 10h-22h');

--------------------------------------------------------------------------------
-- 4. ITEMS
--------------------------------------------------------------------------------
INSERT INTO items (user_id, tag_id, attach_tag_date, nf_key, nf_create_data, nf_photo_url, name, category, description, image, status) VALUES
('11111111-1111-1111-1111-111111111111', 'TAG-0001', SYSTIMESTAMP - 45, 'NF-2026-000123', DATE '2026-06-01', NULL, 'iPhone 14 Pro', 1, 'Smartphone cor grafite, 256GB', NULL, 'active');
INSERT INTO items (user_id, tag_id, attach_tag_date, nf_key, nf_create_data, nf_photo_url, name, category, description, image, status) VALUES
('22222222-2222-2222-2222-222222222222', 'TAG-0002', SYSTIMESTAMP - 40, 'NF-2026-000456', DATE '2026-05-15', NULL, 'Carteira de couro', 2, 'Carteira marrom com documentos pessoais', NULL, 'lost');
INSERT INTO items (user_id, tag_id, attach_tag_date, nf_key, nf_create_data, nf_photo_url, name, category, description, image, status) VALUES
('33333333-3333-3333-3333-333333333333', 'TAG-0003', SYSTIMESTAMP - 35, NULL, NULL, NULL, 'Molho de chaves', 3, 'Chaves de casa e carro com chaveiro azul', NULL, 'active');
INSERT INTO items (user_id, tag_id, attach_tag_date, nf_key, nf_create_data, nf_photo_url, name, category, description, image, status) VALUES
('44444444-4444-4444-4444-444444444444', 'TAG-0004', SYSTIMESTAMP - 25, 'NF-2026-000789', DATE '2026-07-10', NULL, 'Mochila Notebook Dell', 4, 'Mochila preta com notebook Dell dentro', NULL, 'stolen');
INSERT INTO items (user_id, tag_id, attach_tag_date, nf_key, nf_create_data, nf_photo_url, name, category, description, image, status) VALUES
('55555555-5555-5555-5555-555555555555', 'TAG-0005', SYSTIMESTAMP - 10, NULL, NULL, NULL, 'Óculos Ray-Ban', 5, 'Óculos de sol modelo aviador', NULL, 'active');

--------------------------------------------------------------------------------
-- 5. ALERTS
--------------------------------------------------------------------------------
INSERT INTO alerts (item_id, type, last_seen_lat, last_seen_lng, last_seen_address, incident_date, radius_km, status, description) VALUES
(2, 'lost', -16.6799, -49.2550, 'Praça Cívica, Goiânia - GO', '2026-08-20', 5, 'active', 'Perdida durante evento na praça');
INSERT INTO alerts (item_id, type, last_seen_lat, last_seen_lng, last_seen_address, incident_date, radius_km, status, description) VALUES
(4, 'stolen', -16.7090, -49.2680, 'Av. T-9, Setor Bueno, Goiânia - GO', '2026-09-01', 10, 'active', 'Furtada de dentro do carro');

--------------------------------------------------------------------------------
-- 6. FOUND_REPORTS
--------------------------------------------------------------------------------
INSERT INTO found_reports (item_id, finder_id, found_lat, found_lng, found_address, found_date, notes, is_anonymous, alert_id) VALUES
(2, '33333333-3333-3333-3333-333333333333', -16.6805, -49.2560, 'Próximo à Praça Cívica, Goiânia - GO', SYSTIMESTAMP - 5, 'Encontrada caída próxima ao banco da praça', 0, 1);

--------------------------------------------------------------------------------
-- 7. RETURN_PROCESSES
--------------------------------------------------------------------------------
INSERT INTO return_processes (alert_id, found_report_id, return_type, partner_point_id, delivery_fee, return_code, status) VALUES
(1, 1, 'partner_point', 1, 0.00, 'RET-0001', 'ready_for_pickup');

--------------------------------------------------------------------------------
-- 8. NOTIFICATIONS
--------------------------------------------------------------------------------
INSERT INTO notifications (user_id, title, message, is_read) VALUES
('22222222-2222-2222-2222-222222222222', 'Item encontrado!', 'Sua carteira de couro foi encontrada e está disponível para retirada.', 0);
INSERT INTO notifications (user_id, title, message, is_read) VALUES
('44444444-4444-4444-4444-444444444444', 'Alerta criado', 'Seu alerta de furto foi registrado com sucesso.', 1);
INSERT INTO notifications (user_id, title, message, is_read) VALUES
('33333333-3333-3333-3333-333333333333', 'Obrigado por ajudar!', 'Seu relato de item encontrado está em análise.', 0);

--------------------------------------------------------------------------------
-- 9. REVIEWS
--------------------------------------------------------------------------------
INSERT INTO reviews (return_process_id, reviewer_id, rating, comment_text) VALUES
(1, '22222222-2222-2222-2222-222222222222', 5, 'Processo rápido e seguro, recomendo!');

--------------------------------------------------------------------------------
-- 10. COMPANIES
--------------------------------------------------------------------------------
INSERT INTO companies (owner_id, name, trade_name, cnpj, email, phone, address, city, state) VALUES
('11111111-1111-1111-1111-111111111111', 'TechFind Soluções LTDA', 'TechFind', '12.345.678/0001-90', 'contato@techfind.com', '(62) 3222-1000', 'Av. Anhanguera, 2000 - Centro', 'Goiânia', 'GO');

--------------------------------------------------------------------------------
-- 11. COMPANY_EMPLOYEES
--------------------------------------------------------------------------------
INSERT INTO company_employees (company_id, user_id, email, name, role, unit, status, linked_at)
SELECT c.id, '55555555-5555-5555-5555-555555555555', 'pedro.costa@email.com', 'Pedro Costa', 'Operação', 'Goiânia', 'Ativo', SYSTIMESTAMP - 15
FROM companies c WHERE c.cnpj = '12.345.678/0001-90';

COMMIT;
