--------------------------------------------------------------------------------
-- 0. LIMPEZA
--------------------------------------------------------------------------------
-- DROP TABLE reviews CASCADE CONSTRAINTS PURGE;
-- DROP TABLE return_processes CASCADE CONSTRAINTS PURGE;
-- DROP TABLE found_reports CASCADE CONSTRAINTS PURGE;
-- DROP TABLE alerts CASCADE CONSTRAINTS PURGE;
-- DROP TABLE notifications CASCADE CONSTRAINTS PURGE;
-- DROP TABLE company_employees CASCADE CONSTRAINTS PURGE;
-- DROP TABLE companies CASCADE CONSTRAINTS PURGE;
-- DROP TABLE items CASCADE CONSTRAINTS PURGE;
-- DROP TABLE category CASCADE CONSTRAINTS PURGE;
-- DROP TABLE partner_points CASCADE CONSTRAINTS PURGE;
-- DROP TABLE app_users CASCADE CONSTRAINTS PURGE;

--------------------------------------------------------------------------------
-- 1. APP_USERS
--------------------------------------------------------------------------------
CREATE TABLE app_users (
  id            VARCHAR2(36)    NOT NULL,
  email         VARCHAR2(255)   NOT NULL,
  full_name     VARCHAR2(255),
  created_at    TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT app_users_pkey PRIMARY KEY (id),
  CONSTRAINT app_users_email_uk UNIQUE (email)
);

--------------------------------------------------------------------------------
-- 2. CATEGORY
--------------------------------------------------------------------------------
CREATE TABLE category (
  id            NUMBER GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at    TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  name          VARCHAR2(255),
  CONSTRAINT category_pkey PRIMARY KEY (id)
);

--------------------------------------------------------------------------------
-- 3. PARTNER_POINTS
--------------------------------------------------------------------------------
CREATE TABLE partner_points (
  id             NUMBER GENERATED ALWAYS AS IDENTITY NOT NULL,
  name           VARCHAR2(255)     NOT NULL,
  address        CLOB              NOT NULL,
  latitude       BINARY_DOUBLE,
  longitude      BINARY_DOUBLE,
  working_hours  VARCHAR2(255),
  created_at     TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT partner_points_pkey PRIMARY KEY (id)
);

--------------------------------------------------------------------------------
-- 4. ITEMS
--------------------------------------------------------------------------------
CREATE TABLE items (
  id                NUMBER GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id           VARCHAR2(36),
  tag_id            VARCHAR2(255),
  attach_tag_date   TIMESTAMP WITH TIME ZONE,
  nf_key            VARCHAR2(255),
  nf_create_data    DATE,
  nf_photo_url      VARCHAR2(500),
  name              VARCHAR2(255)   NOT NULL,
  category          NUMBER          NOT NULL,
  description       CLOB,
  created_at        TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  image             VARCHAR2(500),
  status            VARCHAR2(4000),
  CONSTRAINT items_pkey PRIMARY KEY (id),
  CONSTRAINT items_tag_id_uk UNIQUE (tag_id),
  CONSTRAINT items_nf_key_uk UNIQUE (nf_key),
  CONSTRAINT items_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_users(id),
  CONSTRAINT items_category_fkey FOREIGN KEY (category) REFERENCES category(id)
);

--------------------------------------------------------------------------------
-- 5. ALERTS
--------------------------------------------------------------------------------
CREATE TABLE alerts (
  id                NUMBER GENERATED ALWAYS AS IDENTITY NOT NULL,
  item_id           NUMBER,
  type              VARCHAR2(20)    NOT NULL,
  last_seen_lat     BINARY_DOUBLE,
  last_seen_lng     BINARY_DOUBLE,
  last_seen_address CLOB,
  incident_date     VARCHAR2(255)   NOT NULL,
  radius_km         NUMBER DEFAULT 5,
  status            VARCHAR2(20) DEFAULT 'active',
  created_at        TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  description       CLOB,
  CONSTRAINT alerts_pkey PRIMARY KEY (id),
  CONSTRAINT alerts_item_id_fkey FOREIGN KEY (item_id) REFERENCES items(id),
  CONSTRAINT alerts_type_chk CHECK (type IN ('lost', 'stolen')),
  CONSTRAINT alerts_status_chk CHECK (status IN ('active', 'resolved', 'canceled'))
);

--------------------------------------------------------------------------------
-- 6. FOUND_REPORTS
--------------------------------------------------------------------------------
CREATE TABLE found_reports (
  id            NUMBER GENERATED ALWAYS AS IDENTITY NOT NULL,
  item_id       NUMBER,
  finder_id     VARCHAR2(36),
  found_lat     BINARY_DOUBLE,
  found_lng     BINARY_DOUBLE,
  found_address CLOB,
  found_date    TIMESTAMP WITH TIME ZONE NOT NULL,
  notes         CLOB,
  is_anonymous  NUMBER(1) DEFAULT 0,
  created_at    TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  alert_id      NUMBER,
  CONSTRAINT found_reports_pkey PRIMARY KEY (id),
  CONSTRAINT found_reports_finder_id_fkey FOREIGN KEY (finder_id) REFERENCES app_users(id),
  CONSTRAINT found_reports_alert_id_fkey FOREIGN KEY (alert_id) REFERENCES alerts(id),
  CONSTRAINT found_reports_item_id_fkey FOREIGN KEY (item_id) REFERENCES items(id),
  CONSTRAINT found_reports_anonymous_chk CHECK (is_anonymous IN (0,1))
);

--------------------------------------------------------------------------------
-- 7. RETURN_PROCESSES
--------------------------------------------------------------------------------
CREATE TABLE return_processes (
  id                NUMBER GENERATED ALWAYS AS IDENTITY NOT NULL,
  alert_id          NUMBER,
  found_report_id   NUMBER,
  return_type       VARCHAR2(20)    NOT NULL,
  partner_point_id  NUMBER,
  delivery_fee      NUMBER(10,2) DEFAULT 0.00,
  return_code       VARCHAR2(50),
  status            VARCHAR2(20) DEFAULT 'pending',
  created_at        TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT return_processes_pkey PRIMARY KEY (id),
  CONSTRAINT return_processes_return_code_uk UNIQUE (return_code),
  CONSTRAINT return_processes_alert_id_fkey FOREIGN KEY (alert_id) REFERENCES alerts(id),
  CONSTRAINT return_processes_found_report_id_fkey FOREIGN KEY (found_report_id) REFERENCES found_reports(id),
  CONSTRAINT return_processes_partner_point_id_fkey FOREIGN KEY (partner_point_id) REFERENCES partner_points(id),
  CONSTRAINT return_processes_type_chk CHECK (return_type IN ('partner_point', 'home_delivery')),
  CONSTRAINT return_processes_status_chk CHECK (status IN ('pending', 'with_finder', 'in_transit', 'ready_for_pickup', 'completed'))
);

--------------------------------------------------------------------------------
-- 8. NOTIFICATIONS
--------------------------------------------------------------------------------
CREATE TABLE notifications (
  id          NUMBER GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id     VARCHAR2(36),
  title       VARCHAR2(255)   NOT NULL,
  message     CLOB            NOT NULL,
  is_read     NUMBER(1) DEFAULT 0,
  created_at  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT notifications_pkey PRIMARY KEY (id),
  CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_users(id),
  CONSTRAINT notifications_is_read_chk CHECK (is_read IN (0,1))
);

--------------------------------------------------------------------------------
-- 9. REVIEWS
--------------------------------------------------------------------------------
CREATE TABLE reviews (
  id                  NUMBER GENERATED ALWAYS AS IDENTITY NOT NULL,
  return_process_id   NUMBER,
  reviewer_id         VARCHAR2(36),
  rating              NUMBER          NOT NULL,
  comment_text        CLOB,
  created_at          TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT reviews_pkey PRIMARY KEY (id),
  CONSTRAINT reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES app_users(id),
  CONSTRAINT reviews_return_process_id_fkey FOREIGN KEY (return_process_id) REFERENCES return_processes(id),
  CONSTRAINT reviews_rating_chk CHECK (rating >= 1 AND rating <= 5)
);

--------------------------------------------------------------------------------
-- 10. COMPANIES
--------------------------------------------------------------------------------
CREATE TABLE companies (
  id            VARCHAR2(36)    DEFAULT SYS_GUID() NOT NULL,
  owner_id      VARCHAR2(36),
  name          VARCHAR2(255)   NOT NULL,
  trade_name    VARCHAR2(255),
  cnpj          VARCHAR2(20),
  email         VARCHAR2(255),
  phone         VARCHAR2(30),
  address       CLOB,
  city          VARCHAR2(100) DEFAULT 'Goiânia',
  state         VARCHAR2(2)   DEFAULT 'GO',
  logo_url      VARCHAR2(500),
  created_at    TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP,
  updated_at    TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP,
  CONSTRAINT companies_pkey PRIMARY KEY (id),
  CONSTRAINT companies_cnpj_uk UNIQUE (cnpj),
  CONSTRAINT companies_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES app_users(id)
);

--------------------------------------------------------------------------------
-- 11. COMPANY_EMPLOYEES
--------------------------------------------------------------------------------
CREATE TABLE company_employees (
  id            VARCHAR2(36)    DEFAULT SYS_GUID() NOT NULL,
  company_id    VARCHAR2(36)    NOT NULL,
  user_id       VARCHAR2(36),
  email         VARCHAR2(255)   NOT NULL,
  name          VARCHAR2(255)   NOT NULL,
  role          VARCHAR2(100) DEFAULT 'Operação' NOT NULL,
  unit          VARCHAR2(100) DEFAULT 'Goiânia' NOT NULL,
  status        VARCHAR2(50)  DEFAULT 'Pendente' NOT NULL,
  created_at    TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP,
  linked_at     TIMESTAMP WITH TIME ZONE,
  CONSTRAINT company_employees_pkey PRIMARY KEY (id),
  CONSTRAINT company_employees_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id),
  CONSTRAINT company_employees_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_users(id)
);

--------------------------------------------------------------------------------
-- INDICES ADICIONAIS (FKs nao geram indice automatico no Oracle, diferente do Postgres em PKs)
--------------------------------------------------------------------------------
CREATE INDEX idx_items_user_id ON items(user_id);
CREATE INDEX idx_items_category ON items(category);
CREATE INDEX idx_alerts_item_id ON alerts(item_id);
CREATE INDEX idx_found_reports_item_id ON found_reports(item_id);
CREATE INDEX idx_found_reports_finder_id ON found_reports(finder_id);
CREATE INDEX idx_found_reports_alert_id ON found_reports(alert_id);
CREATE INDEX idx_return_processes_alert_id ON return_processes(alert_id);
CREATE INDEX idx_return_processes_found_report_id ON return_processes(found_report_id);
CREATE INDEX idx_return_processes_partner_point_id ON return_processes(partner_point_id);
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_reviews_return_process_id ON reviews(return_process_id);
CREATE INDEX idx_reviews_reviewer_id ON reviews(reviewer_id);
CREATE INDEX idx_company_employees_company_id ON company_employees(company_id);
CREATE INDEX idx_company_employees_user_id ON company_employees(user_id);

COMMIT;
