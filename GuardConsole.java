/* Fraud Management System - Nikitha Bharath, 25BCE2517 */
import java.sql.*;

/** Bank Guard console JDBC demo: connect, run queries, then CRUD on the customers table. */
public class GuardConsole {
    static final String URL  = env("FRAUD_DB_URL", "jdbc:mysql://localhost:3306/fraud_management");
    static final String USER = env("FRAUD_DB_USER", "root");
    static final String PASS = env("FRAUD_DB_PASS", "");
    static String env(String k, String d) { String v = System.getenv(k); return v == null ? d : v; }

    static void printQuery(Connection c, String title, String sql) throws SQLException {
        System.out.println("\n" + title);
        try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery(sql)) {
            int n = rs.getMetaData().getColumnCount();
            while (rs.next()) {
                StringBuilder sb = new StringBuilder();
                for (int i = 1; i <= n; i++) { if (i > 1) sb.append(" | "); sb.append(rs.getString(i)); }
                System.out.println(sb);
            }
        }
    }

    static int runUpdate(Connection c, String sql, Object... args) throws SQLException {
        try (PreparedStatement ps = c.prepareStatement(sql)) {
            for (int i = 0; i < args.length; i++) ps.setObject(i + 1, args[i]);
            return ps.executeUpdate();
        }
    }

    public static void main(String[] args) {
        try (Connection con = DriverManager.getConnection(URL, USER, PASS)) {
            System.out.println("=================================");
            System.out.println("   JDBC CONNECTION SUCCESSFUL");
            System.out.println("=================================");

            printQuery(con, "1. ALL CUSTOMERS", "SELECT customer_number, full_name, access_level, standing FROM customers");
            printQuery(con, "2. ACCOUNTS WITH OWNER (JOIN)",
                "SELECT a.account_number, c.full_name, a.balance, a.status FROM bank_accounts a JOIN customers c ON a.belongs_to = c.customer_number");
            printQuery(con, "3. TRANSACTIONS ABOVE INR 10,000",
                "SELECT txn_ref, kind, amount, status FROM payment_transactions WHERE amount > 10000 ORDER BY amount DESC");
            printQuery(con, "4. OPEN FRAUD ALERTS WITH RULE NAME (JOIN)",
                "SELECT a.alert_ref, a.txn_ref, r.rule_name, a.severity FROM fraud_alerts a JOIN detection_rules r ON a.rule_ref = r.rule_ref WHERE a.alert_status = 'Open'");
            printQuery(con, "5. GROUP BY - ALERTS PER SEVERITY",
                "SELECT severity, COUNT(*) AS alerts FROM fraud_alerts GROUP BY severity ORDER BY alerts DESC");
            printQuery(con, "6. GROUP BY + HAVING - TRANSACTIONS WITH 2+ ALERTS",
                "SELECT txn_ref, COUNT(*) AS alerts FROM fraud_alerts GROUP BY txn_ref HAVING COUNT(*) >= 2");
            printQuery(con, "7. UNTRUSTED DEVICES", "SELECT device_ref, device_name, registered_to FROM devices WHERE trusted = 'No'");
            printQuery(con, "8. NAMES STARTING WITH 'A' (LIKE)", "SELECT customer_number, full_name FROM customers WHERE full_name LIKE 'A%'");

            // ---- CRUD on customers ----
            String id = "CUST-1099";
            runUpdate(con, "DELETE FROM customers WHERE customer_number = ?", id);   // safe to re-run
            System.out.println("\nCRUD 1. CREATE - INSERT");
            int n = runUpdate(con, "INSERT INTO customers (customer_number, full_name, email, access_level, joined_on, standing) VALUES (?,?,?,?,CURDATE(),?)",
                         id, "Arun Kumar", "arun.kumar@example.com", "Standard", "Active");
            System.out.println(n + " customer inserted.");
            printQuery(con, "CRUD 2. READ - SELECT", "SELECT customer_number, full_name, standing FROM customers WHERE customer_number = '" + id + "'");
            System.out.println("\nCRUD 3. UPDATE");
            System.out.println(runUpdate(con, "UPDATE customers SET standing = ? WHERE customer_number = ?", "Suspended", id) + " customer updated.");
            printQuery(con, "Customer after UPDATE:", "SELECT customer_number, full_name, standing FROM customers WHERE customer_number = '" + id + "'");
            System.out.println("\nCRUD 4. DELETE");
            System.out.println(runUpdate(con, "DELETE FROM customers WHERE customer_number = ?", id) + " customer deleted.");
        } catch (SQLException e) {
            System.out.println("Database Error:");
            e.printStackTrace();
            return;
        }
        System.out.println("\n=================================");
        System.out.println("   DATABASE CONNECTION CLOSED");
        System.out.println("=================================");
    }
}
