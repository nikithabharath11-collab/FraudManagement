# DBMS ASSESSMENT – 9
## JDBC CONNECTIVITY – FRAUD MANAGEMENT SYSTEM (Backend + Frontend)
**Name / Reg. No.:** Nikitha Bharath / 25BCE2517  **Dataset:** Fraud Management Data Model (8 tables)

---

## STEPS TO REACHING CONNECTIVITY

### 1. REQUIREMENTS
1. MySQL (8.0)
2. MySQL Connector/J JAR file
3. JDK 25
4. VS Code

### PART 1. INSTALLING THE JAR FILE AND EXTRACTING IT
Download Connector/J, extract it, and copy `mysql-connector-j-26.7.0.jar` into the `jdbc_driver` folder of the project.
> 📷 *Screenshot: Downloads → extracted connector folder*

### MYSQL
```
mysql --version
```
> 📷 *Screenshot: MySQL version output*

### JDK 25
```
java -version
javac -version
```
> 📷 *Screenshot: JDK 25 version output*

### EXECUTION FLOW
```
Java 25
  ↓
Check MySQL
  ↓
Create database  (fraud_management)
  ↓
Create 8 tables + sample data  (database/guard_schema.sql)
  ↓
Test SQL
  ↓
VS Code
  ↓
Add the JDBC .jar to jdbc_driver
  ↓
Write Java JDBC program (GuardConsole.java) and backend (GuardServer.java)
  ↓
Execute SQL through Java  →  Frontend (dashboard/index.html)
```

### CREATING THE DATABASE
```
mysql -u root -p < database/guard_schema.sql
```
Then verify:
```sql
USE fraud_management;
SHOW TABLES;
SELECT * FROM customers;
```
> 📷 *Screenshot: SHOW TABLES and SELECT output*

Tables: `customers, bank_accounts, devices, merchants, payment_transactions, detection_rules, fraud_alerts, activity_log`
(PK/FK exactly as in the ER diagram; see `database/guard_schema.sql`.)

---

## PART 2. ESTABLISHING CONNECTIVITY THROUGH JAVA IN VS CODE

### Project structure (as shown in the VS Code Explorer)
```
FraudManagement
├── jdbc_driver
│   └── mysql-connector-j-26.7.0.jar      ← MySQL connector goes here
├── database
│   └── guard_schema.sql                  ← tables, sample data, views, trigger, procedure
├── dashboard
│   └── index.html                        ← frontend
├── hosting                               ← only used for the Render deployment (Part 4)
│   ├── launch.sh
│   ├── mariadb_small.cnf
│   └── router.conf
├── GuardConsole.java                     ← console JDBC demo (queries + CRUD)
├── GuardServer.java                      ← backend (JDBC + rule engine + REST)
├── Dockerfile, render.yaml, .dockerignore
└── REPORT.md
```
> 📷 *Screenshot: VS Code Explorer showing this structure*

### Connection code (inside GuardConsole.java)
```java
String url = "jdbc:mysql://localhost:3306/fraud_management";
Connection con = DriverManager.getConnection(url, "root", password);
System.out.println("JDBC CONNECTION SUCCESSFUL!");
```
The password is read from the environment variable `FRAUD_DB_PASS`, so it never sits in the source file.

### Set the password (PowerShell, in the VS Code terminal)
```
$env:FRAUD_DB_PASS = "your_mysql_password"
```

### Compile the Java programs
```
javac -cp ".;jdbc_driver\mysql-connector-j-26.7.0.jar" GuardConsole.java GuardServer.java
```
### Run the JDBC program
```
java -cp ".;jdbc_driver\mysql-connector-j-26.7.0.jar" GuardConsole
```

### QUERIES EXECUTED ALONG THE WAY
| # | Query | Purpose |
|---|-------|---------|
| 1 | `SELECT … FROM customers` | All customers |
| 2 | `bank_accounts JOIN customers` | Accounts with owner |
| 3 | `WHERE amount > 10000 ORDER BY amount DESC` | High-value transactions |
| 4 | `fraud_alerts JOIN detection_rules WHERE alert_status='Open'` | Open alerts with rule names |
| 5 | `GROUP BY severity` | Alerts per severity |
| 6 | `GROUP BY txn_ref HAVING COUNT(*) >= 2` | Transactions with 2+ alerts |
| 7 | `WHERE trusted = 'No'` | Untrusted devices |
| 8 | `WHERE full_name LIKE 'A%'` | Names starting with A |

### EXPECTED OUTPUT (with the supplied sample data)
```
=================================
   JDBC CONNECTION SUCCESSFUL
=================================

1. ALL CUSTOMERS
CUST-1001 | Ananya Rao | Standard | Active
CUST-1002 | Vikram Sethi | Standard | Active
CUST-1003 | Meera Iyer | Administrator | Active
CUST-1004 | Rohan Das | Standard | Suspended

3. TRANSACTIONS ABOVE INR 10,000
TXN-3004 | Withdrawal | 98000.00 | Under Review
TXN-3002 | Transfer | 45000.00 | Completed

4. OPEN FRAUD ALERTS WITH RULE NAME (JOIN)
ALRT-7001 | TXN-3004 | Large Withdrawal Watch | High
ALRT-7002 | TXN-3004 | New Device Check | High

5. GROUP BY - ALERTS PER SEVERITY
High | 2
Low | 2

6. GROUP BY + HAVING - TRANSACTIONS WITH 2+ ALERTS
TXN-3004 | 2

7. UNTRUSTED DEVICES
DEV-4004 | Unknown Android Device | CUST-1004

8. NAMES STARTING WITH 'A' (LIKE)
CUST-1001 | Ananya Rao
```
> 📷 *Replace/attach with your own terminal screenshot of the real run.*

### CRUD OPERATIONS (on `customers`)
Uses `PreparedStatement` (parameterised queries) to avoid SQL injection.
```
CRUD 1. CREATE - INSERT      → 1 customer inserted.
CRUD 2. READ - SELECT        → CUST-1099 | Arun Kumar | Active
CRUD 3. UPDATE               → 1 customer updated.   (standing → Suspended)
CRUD 4. DELETE               → 1 customer deleted.
```
> 📷 *Screenshot: CRUD output*

---

## PART 3. BACKEND + FRONTEND ON TOP OF THE JDBC CONNECTION

### Architecture
```
Browser (dashboard/index.html)  ──fetch /api/*──►  GuardServer.java  ──JDBC──►  MySQL: fraud_management
```

### Run the backend
```
java -cp ".;jdbc_driver\mysql-connector-j-26.7.0.jar" GuardServer
```
Console prints `JDBC CONNECTION SUCCESSFUL -> jdbc:mysql://localhost:3306/fraud_management`. Open **http://localhost:8080**; the badge at the top right turns green: **"JDBC connected · MySQL"**.
> 📷 *Screenshot: terminal + browser with the green "JDBC connected" badge*

### REST endpoints
| Method | Path | Action |
|---|---|---|
| GET | `/api/summary` | Dashboard counts |
| GET | `/api/customers · accounts · devices · merchants · rules · transactions · alerts · logs` | List a table |
| GET | `/api/risk · riskscores · statements` | Views and stored procedure (Parts 5 and 6) |
| POST | `/api/transactions` | Insert a transaction, run all enabled rules, create alerts + audit log (one DB transaction) |
| POST | `/api/alerts/review` | Administrator clears / confirms an alert |
| POST | `/api/customers/add · standing · delete` | Customer CRUD |

### Rule engine (in `GuardServer.checkTransaction`)
| Rule | Fires when | Severity |
|---|---|---|
| RULE-6001 Large Withdrawal Watch | Withdrawal > INR 50,000 | High |
| RULE-6002 New Device Check | Device is not trusted | High |
| RULE-6003 Odd Hours Activity | Time between 23:00 and 05:00 | Low |
| RULE-6004 High Risk Merchant | Merchant risk = High (rule disabled in sample data) | Medium |

Clean transactions are `Completed` and debit the balance. Flagged ones become `Under Review`, set `flagged = Yes`, create one `fraud_alerts` row per rule hit, and always write an `activity_log` row. Reviewing an alert as an Administrator clears the transaction (or blocks it on *Confirmed Fraud*).

### Try it in the frontend
1. **Transactions** → ACC-2001, DEV-4004 (untrusted), MER-5003, Purchase, 2000 → status *Under Review*, 1 alert (RULE-6002).
2. Same with *Simulate hour* = 2 → 2 alerts (device + odd hours).
3. **Fraud Alerts** → review as Meera Iyer → alert cleared, transaction completes.
4. **Customers** → add / update standing / delete (deleting CUST-1001 fails: it owns an account, so the FK blocks it).
> 📷 *Screenshots: dashboard, new transaction result, alert review*

---

## PART 4. DEPLOYING ON RENDER

I put the project online on Render (free plan) using Docker, so it runs without my laptop.

### What is inside the container
```
Browser  ──►  nginx ($PORT)  ──►  GuardServer.java (8081)  ──JDBC──►  MariaDB: fraud_management
                              └─►  ShopServer.java (8082)  ──JDBC──►  MariaDB: order_management
```
MariaDB is used instead of MySQL (same SQL, same Connector/J). Abhay's Product Order Management project runs in the same container under `/orders/`, because the free plan gives enough hours for only one service running all day.

### Files added for deployment
| File | Use |
|---|---|
| `Dockerfile` | Compiles the Java files (JDK 21), downloads Connector/J into `jdbc_driver`, installs MariaDB + nginx |
| `hosting/launch.sh` | Starts the database, loads `database/guard_schema.sql` the first time, then both servers and nginx |
| `hosting/mariadb_small.cnf` | Small MariaDB memory settings (free plan has 512 MB) |
| `hosting/router.conf` | Sends `/orders/` to ShopServer and everything else to GuardServer |
| `render.yaml` | Render settings |

For hosting, `GuardServer.java` reads the port from `PORT` (default 8080) so Render can choose it.

### Test it locally
```
docker build -t fraudmgmt .
docker run --rm -m 512m -p 8080:8080 fraudmgmt
```
Open **http://localhost:8080** (fraud) and **http://localhost:8080/orders/** (orders).

### Live links
- https://fraud-management-nikitha.onrender.com
- https://fraudmgmt.onrender.com (same backend, API at `/api/*`)

Note: on the free plan the disk is not saved, so the database goes back to the sample data after every restart.

---

## PART 5. EXTRA DBMS PARTS

I added three small things at the end of `database/guard_schema.sql`. Nothing in the 8 original tables, the sample data or the old endpoints changed.

### 1. View `customer_risk_summary`
One row per customer: number of accounts, transactions, flagged transactions, open alerts and total amount. Each column is a small subquery that joins through `bank_accounts` to that customer.
```sql
SELECT * FROM customer_risk_summary;
```
It is shown in the new **Risk Summary** tab, through `GET /api/risk`.

### 2. Indexes
```sql
CREATE INDEX idx_txn_flagged  ON payment_transactions (flagged);
CREATE INDEX idx_alert_status ON fraud_alerts (alert_status);
CREATE INDEX idx_log_time     ON activity_log (event_time);
```
These are the columns the dashboard filters on (`flagged = 'Yes'`, `alert_status = 'Open'`) and the activity log sorts on. Check with `SHOW INDEX FROM payment_transactions;`.

### 3. Trigger `trg_balance_history`
A new table `account_balance_history` keeps the old and new balance every time a row in `bank_accounts` changes balance (for example when a clean transaction debits the account). The trigger needs `DELIMITER $$` because its body has `;` inside.
```sql
SELECT * FROM account_balance_history;
```
> 📷 *Screenshot: Risk Summary tab, SHOW INDEX output, balance history after a transaction*

---

## PART 6. BANK GUARD THEME AND TWO NEW FEATURES

### Theme
I gave the project a "Bank Guard" theme: the backend guards the bank's accounts, and the names of folders, files and classes now say what each part does. The title is still **Fraud Management System**, and all old routes, JSON, tables and sample data are the same.

| Old name | New name |
|---|---|
| `LIB/` | `jdbc_driver/` |
| `sql/schema.sql` | `database/guard_schema.sql` |
| `web/index.html` | `dashboard/index.html` |
| `deploy/start.sh`, `db.cnf`, `nginx.conf` | `hosting/launch.sh`, `mariadb_small.cnf`, `router.conf` |
| `FraudServer.java` | `GuardServer.java` |
| `JDBCExample.java` | `GuardConsole.java` |
| `VIEWS`, `handle`, `route`, `newTxn`, `review`, `hits` | `READ_QUERIES`, `handleRequest`, `handleApi`, `checkTransaction`, `reviewAlert`, `ruleHits` |
| `show`, `exec` (console) | `printQuery`, `runUpdate` |

Compile and run with the new names:
```
javac -cp ".;jdbc_driver\mysql-connector-j-26.7.0.jar" GuardConsole.java GuardServer.java
java -cp ".;jdbc_driver\mysql-connector-j-26.7.0.jar" GuardConsole
java -cp ".;jdbc_driver\mysql-connector-j-26.7.0.jar" GuardServer
```

### 4. View `transaction_risk_scores` (tab **Risk Scores**, `GET /api/riskscores`)
Gives every transaction a score from 0 to 100, worked out in SQL:
- the inner `SELECT` joins `payment_transactions` with `merchants` and `devices`;
- four `CASE` expressions add points: amount over 50,000 = 40 (over 10,000 = 20), High-risk merchant = 30 (Medium = 15), untrusted device = 20, hour between 23:00 and 05:00 = 10;
- the outer `SELECT` reads that sum from the subquery and turns it into a band: 60+ High, 30+ Medium, else Low.
```sql
SELECT * FROM transaction_risk_scores ORDER BY risk_score DESC;
```
With the sample data TXN-3004 (98,000 withdrawal, high-risk exchange, untrusted device) scores 90 / High. The score is only for display; the rule engine still decides the status.

### 5. Stored procedure `monthly_statement` (tab **Monthly Statements**, `GET /api/statements`)
One row per account per month: number of transactions, total of completed amounts, number of flagged transactions and the current balance. It joins `payment_transactions → bank_accounts → customers`, groups by account and `DATE_FORMAT(txn_datetime, '%Y-%m')`, and uses `SUM(CASE ...)` to count only completed amounts and flagged rows. The parameter picks one account; `NULL` means all (that is what the tab uses). It needs `DELIMITER $$` like the trigger.
```sql
CALL monthly_statement('ACC-2001');
CALL monthly_statement(NULL);
```
> 📷 *Screenshot: Risk Scores tab, Monthly Statements tab, CALL output in MySQL*

I used AI assistance for parts of the code and deployment, as allowed for this project.
