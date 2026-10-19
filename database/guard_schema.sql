-- Fraud Management System: schema + sample data (MySQL 8)
-- Nikitha Bharath, 25BCE2517
CREATE DATABASE IF NOT EXISTS fraud_management;
USE fraud_management;

DROP TABLE IF EXISTS account_balance_history;
DROP TABLE IF EXISTS activity_log, fraud_alerts, payment_transactions, detection_rules, merchants, devices, bank_accounts, customers;

CREATE TABLE customers (
  customer_number VARCHAR(12) PRIMARY KEY,
  full_name       VARCHAR(100) NOT NULL,
  email           VARCHAR(120) NOT NULL,
  access_level    VARCHAR(20)  NOT NULL,          -- Standard / Administrator
  joined_on       DATE,
  last_login      DATETIME,
  standing        VARCHAR(20)  NOT NULL           -- Active / Suspended
);
CREATE TABLE bank_accounts (
  account_number VARCHAR(12) PRIMARY KEY,
  belongs_to     VARCHAR(12) NOT NULL,
  account_label  VARCHAR(80),
  account_type   VARCHAR(20),
  balance        DECIMAL(14,2) NOT NULL,
  currency       VARCHAR(3) NOT NULL,
  status         VARCHAR(20) NOT NULL,            -- Active / Frozen
  created_on     DATE,
  FOREIGN KEY (belongs_to) REFERENCES customers(customer_number)
);
CREATE TABLE devices (
  device_ref    VARCHAR(12) PRIMARY KEY,
  registered_to VARCHAR(12) NOT NULL,
  device_type   VARCHAR(20),
  device_name   VARCHAR(80),
  first_seen    DATE,
  last_used     DATETIME,
  trusted       VARCHAR(3) NOT NULL,              -- Yes / No
  FOREIGN KEY (registered_to) REFERENCES customers(customer_number)
);
CREATE TABLE merchants (
  merchant_ref  VARCHAR(12) PRIMARY KEY,
  merchant_name VARCHAR(80) NOT NULL,
  category      VARCHAR(40),
  location      VARCHAR(60),
  risk_level    VARCHAR(10) NOT NULL,             -- Low / Medium / High
  onboarded_on  DATE
);
CREATE TABLE detection_rules (
  rule_ref          VARCHAR(12) PRIMARY KEY,
  rule_name         VARCHAR(60) NOT NULL,
  description       VARCHAR(160),
  rule_category     VARCHAR(30),
  trigger_threshold VARCHAR(40),
  enabled           VARCHAR(3) NOT NULL
);
CREATE TABLE payment_transactions (
  txn_ref       VARCHAR(12) PRIMARY KEY,
  from_account  VARCHAR(12) NOT NULL,
  device_ref    VARCHAR(12) NOT NULL,
  merchant_ref  VARCHAR(12) NOT NULL,
  kind          VARCHAR(20) NOT NULL,             -- Purchase / Transfer / Withdrawal
  amount        DECIMAL(12,2) NOT NULL,
  currency      VARCHAR(3) NOT NULL,
  txn_datetime  DATETIME NOT NULL,
  location      VARCHAR(60),
  status        VARCHAR(20) NOT NULL,             -- Completed / Under Review / Blocked
  flagged       VARCHAR(3) NOT NULL,
  FOREIGN KEY (from_account) REFERENCES bank_accounts(account_number),
  FOREIGN KEY (device_ref)   REFERENCES devices(device_ref),
  FOREIGN KEY (merchant_ref) REFERENCES merchants(merchant_ref)
);
CREATE TABLE fraud_alerts (
  alert_ref      VARCHAR(12) PRIMARY KEY,
  txn_ref        VARCHAR(12) NOT NULL,
  rule_ref       VARCHAR(12) NOT NULL,
  severity       VARCHAR(10) NOT NULL,
  alert_status   VARCHAR(20) NOT NULL,            -- Open / Cleared / Confirmed Fraud
  reviewed_by    VARCHAR(12),
  reviewer_notes VARCHAR(200),
  FOREIGN KEY (txn_ref)     REFERENCES payment_transactions(txn_ref),
  FOREIGN KEY (rule_ref)    REFERENCES detection_rules(rule_ref),
  FOREIGN KEY (reviewed_by) REFERENCES customers(customer_number)
);
CREATE TABLE activity_log (
  log_ref        VARCHAR(12) PRIMARY KEY,
  event_type     VARCHAR(30) NOT NULL,
  performed_by   VARCHAR(12) NOT NULL,
  account_number VARCHAR(12),
  txn_ref        VARCHAR(12),
  event_time     DATETIME NOT NULL,
  details        VARCHAR(200),
  FOREIGN KEY (performed_by)   REFERENCES customers(customer_number),
  FOREIGN KEY (account_number) REFERENCES bank_accounts(account_number),
  FOREIGN KEY (txn_ref)        REFERENCES payment_transactions(txn_ref)
);

INSERT INTO customers VALUES
('CUST-1001','Ananya Rao','ananya.rao@example.com','Standard','2023-02-11','2026-07-16 09:12','Active'),
('CUST-1002','Vikram Sethi','vikram.sethi@example.com','Standard','2022-11-05','2026-07-15 21:40','Active'),
('CUST-1003','Meera Iyer','meera.iyer@example.com','Administrator','2021-06-18','2026-07-17 08:03','Active'),
('CUST-1004','Rohan Das','rohan.das@example.com','Standard','2024-01-27','2026-06-30 14:55','Suspended');
INSERT INTO bank_accounts VALUES
('ACC-2001','CUST-1001','Everyday Spending','Savings',84500.00,'INR','Active','2023-02-12'),
('ACC-2002','CUST-1002','Business Reserve','Current',512300.50,'INR','Active','2022-11-06'),
('ACC-2003','CUST-1003','Family Savings','Savings',219000.00,'INR','Active','2021-06-19'),
('ACC-2004','CUST-1004','Travel Fund','Savings',15000.00,'INR','Frozen','2024-01-28');
INSERT INTO devices VALUES
('DEV-4001','CUST-1001','Mobile','Ananya''s iPhone','2023-02-12','2026-07-16 09:10','Yes'),
('DEV-4002','CUST-1002','Desktop','Office Workstation','2022-11-06','2026-07-15 21:38','Yes'),
('DEV-4003','CUST-1003','Mobile','Meera''s Pixel','2021-06-20','2026-07-17 08:00','Yes'),
('DEV-4004','CUST-1004','Mobile','Unknown Android Device','2026-06-29','2026-06-30 14:50','No');
INSERT INTO merchants VALUES
('MER-5001','GreenMart Grocery','Retail','Chennai, IN','Low','2020-04-01'),
('MER-5002','QuickCab Rides','Transport','Bengaluru, IN','Low','2021-09-14'),
('MER-5003','PixelPlay Games','Digital Goods','Online','Medium','2022-03-22'),
('MER-5004','SwiftCoin Exchange','Financial Services','Online','High','2023-08-09');
INSERT INTO detection_rules VALUES
('RULE-6001','Large Withdrawal Watch','Flags withdrawals above a set amount','Amount Based','50000 INR','Yes'),
('RULE-6002','New Device Check','Flags activity from an unrecognized device','Device Based','Untrusted device','Yes'),
('RULE-6003','Odd Hours Activity','Flags transactions made late at night','Time Based','23:00 - 05:00','Yes'),
('RULE-6004','High Risk Merchant','Flags payments to high risk merchants','Merchant Based','Risk = High','No');
INSERT INTO payment_transactions VALUES
('TXN-3001','ACC-2001','DEV-4001','MER-5001','Purchase',1250.00,'INR','2026-07-16 09:15','Chennai, IN','Completed','Yes'),
('TXN-3002','ACC-2002','DEV-4002','MER-5002','Transfer',45000.00,'INR','2026-07-15 21:42','Bengaluru, IN','Completed','Yes'),
('TXN-3003','ACC-2003','DEV-4003','MER-5003','Purchase',3200.00,'INR','2026-07-17 08:05','Chennai, IN','Completed','No'),
('TXN-3004','ACC-2004','DEV-4004','MER-5004','Withdrawal',98000.00,'INR','2026-06-30 14:52','Unknown','Under Review','Yes');
INSERT INTO fraud_alerts VALUES
('ALRT-7001','TXN-3004','RULE-6001','High','Open',NULL,NULL),
('ALRT-7002','TXN-3004','RULE-6002','High','Open',NULL,NULL),
('ALRT-7003','TXN-3002','RULE-6003','Low','Cleared','CUST-1003','Verified with customer, normal activity'),
('ALRT-7004','TXN-3001','RULE-6003','Low','Cleared','CUST-1003','Routine late purchase, no concern');
INSERT INTO activity_log VALUES
('LOG-8001','Login','CUST-1001','ACC-2001',NULL,'2026-07-16 09:10','Signed in from trusted mobile device'),
('LOG-8002','Payment Made','CUST-1001','ACC-2001','TXN-3001','2026-07-16 09:15','Purchase at GreenMart Grocery'),
('LOG-8003','Transfer Sent','CUST-1002','ACC-2002','TXN-3002','2026-07-15 21:42','Transfer to QuickCab Rides account'),
('LOG-8004','Withdrawal Attempt','CUST-1004','ACC-2004','TXN-3004','2026-06-30 14:52','Large withdrawal from unrecognized device');

-- ---------- extra DBMS parts ----------

-- 1. view: one row per customer with their activity and open alerts
CREATE OR REPLACE VIEW customer_risk_summary AS
SELECT c.customer_number, c.full_name, c.standing,
  (SELECT COUNT(*) FROM bank_accounts a WHERE a.belongs_to = c.customer_number) AS accounts,
  (SELECT COUNT(*) FROM payment_transactions t JOIN bank_accounts a ON t.from_account = a.account_number
     WHERE a.belongs_to = c.customer_number) AS transactions,
  (SELECT COUNT(*) FROM payment_transactions t JOIN bank_accounts a ON t.from_account = a.account_number
     WHERE a.belongs_to = c.customer_number AND t.flagged = 'Yes') AS flagged_transactions,
  (SELECT COUNT(*) FROM fraud_alerts f JOIN payment_transactions t ON f.txn_ref = t.txn_ref
     JOIN bank_accounts a ON t.from_account = a.account_number
     WHERE a.belongs_to = c.customer_number AND f.alert_status = 'Open') AS open_alerts,
  (SELECT COALESCE(SUM(t.amount), 0) FROM payment_transactions t JOIN bank_accounts a ON t.from_account = a.account_number
     WHERE a.belongs_to = c.customer_number) AS total_amount
FROM customers c;

-- 2. indexes on columns the app filters and sorts on
CREATE INDEX idx_txn_flagged  ON payment_transactions (flagged);
CREATE INDEX idx_alert_status ON fraud_alerts (alert_status);
CREATE INDEX idx_log_time     ON activity_log (event_time);

-- 3. trigger: keep a history row every time an account balance changes
CREATE TABLE account_balance_history (
  history_id     INT AUTO_INCREMENT PRIMARY KEY,
  account_number VARCHAR(12) NOT NULL,
  old_balance    DECIMAL(14,2) NOT NULL,
  new_balance    DECIMAL(14,2) NOT NULL,
  changed_at     DATETIME NOT NULL,
  FOREIGN KEY (account_number) REFERENCES bank_accounts(account_number)
);

DROP TRIGGER IF EXISTS trg_balance_history;
DELIMITER $$
CREATE TRIGGER trg_balance_history
AFTER UPDATE ON bank_accounts
FOR EACH ROW
BEGIN
  IF NEW.balance <> OLD.balance THEN
    INSERT INTO account_balance_history (account_number, old_balance, new_balance, changed_at)
    VALUES (NEW.account_number, OLD.balance, NEW.balance, NOW());
  END IF;
END$$
DELIMITER ;

-- ---------- Bank Guard additions ----------

-- 4. view: risk score for every transaction (0-100), worked out in SQL
--    amount (up to 40) + merchant risk (up to 30) + untrusted device (20) + odd hours (10)
CREATE OR REPLACE VIEW transaction_risk_scores AS
SELECT x.*,
  CASE WHEN x.risk_score >= 60 THEN 'High'
       WHEN x.risk_score >= 30 THEN 'Medium'
       ELSE 'Low' END AS risk_band
FROM (
  SELECT t.txn_ref, t.from_account, t.kind, t.amount, t.status,
         m.merchant_name, m.risk_level AS merchant_risk, d.trusted AS device_trusted,
         HOUR(t.txn_datetime) AS txn_hour,
         ( CASE WHEN t.amount > 50000 THEN 40 WHEN t.amount > 10000 THEN 20 ELSE 0 END
         + CASE m.risk_level WHEN 'High' THEN 30 WHEN 'Medium' THEN 15 ELSE 0 END
         + CASE WHEN d.trusted = 'No' THEN 20 ELSE 0 END
         + CASE WHEN HOUR(t.txn_datetime) >= 23 OR HOUR(t.txn_datetime) < 5 THEN 10 ELSE 0 END ) AS risk_score
  FROM payment_transactions t
  JOIN merchants m ON t.merchant_ref = m.merchant_ref
  JOIN devices d   ON t.device_ref = d.device_ref
) x;

-- 5. stored procedure: monthly statement for one account (NULL = all accounts)
--    CALL monthly_statement('ACC-2001');
DROP PROCEDURE IF EXISTS monthly_statement;
DELIMITER $$
CREATE PROCEDURE monthly_statement(IN acc VARCHAR(12))
BEGIN
  SELECT a.account_number, c.full_name,
         DATE_FORMAT(t.txn_datetime, '%Y-%m') AS statement_month,
         COUNT(*) AS transactions,
         SUM(CASE WHEN t.status = 'Completed' THEN t.amount ELSE 0 END) AS completed_amount,
         SUM(CASE WHEN t.flagged = 'Yes' THEN 1 ELSE 0 END) AS flagged_transactions,
         a.balance AS current_balance
  FROM payment_transactions t
  JOIN bank_accounts a ON t.from_account = a.account_number
  JOIN customers c     ON a.belongs_to = c.customer_number
  WHERE acc IS NULL OR a.account_number = acc
  GROUP BY a.account_number, c.full_name, statement_month, a.balance
  ORDER BY a.account_number, statement_month;
END$$
DELIMITER ;
