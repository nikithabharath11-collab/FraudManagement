/* Fraud Management System - Nikitha Bharath, 25BCE2517 */
import com.sun.net.httpserver.*;
import java.io.*;
import java.math.BigDecimal;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.sql.*;
import java.time.LocalDateTime;
import java.util.*;

/** Bank Guard backend: tiny HTTP server (JDK only) that checks transactions against the fraud rules over JDBC. */
public class GuardServer {
    static final String URL  = env("FRAUD_DB_URL", "jdbc:mysql://localhost:3306/fraud_management");
    static final String USER = env("FRAUD_DB_USER", "root");
    static final String PASS = env("FRAUD_DB_PASS", "");
    static String env(String k, String d) { String v = System.getenv(k); return v == null ? d : v; }

    static final Map<String, String> READ_QUERIES = new LinkedHashMap<>();
    static {
        READ_QUERIES.put("customers",    "SELECT * FROM customers ORDER BY customer_number");
        READ_QUERIES.put("accounts",     "SELECT * FROM bank_accounts ORDER BY account_number");
        READ_QUERIES.put("devices",      "SELECT * FROM devices ORDER BY device_ref");
        READ_QUERIES.put("merchants",    "SELECT * FROM merchants ORDER BY merchant_ref");
        READ_QUERIES.put("rules",        "SELECT * FROM detection_rules ORDER BY rule_ref");
        READ_QUERIES.put("transactions", "SELECT * FROM payment_transactions ORDER BY txn_datetime DESC");
        READ_QUERIES.put("logs",         "SELECT * FROM activity_log ORDER BY event_time DESC");
        READ_QUERIES.put("risk",         "SELECT * FROM customer_risk_summary ORDER BY open_alerts DESC, flagged_transactions DESC, customer_number");   // view from guard_schema.sql
        READ_QUERIES.put("riskscores",   "SELECT * FROM transaction_risk_scores ORDER BY risk_score DESC, txn_ref");   // view, new
        READ_QUERIES.put("statements",   "CALL monthly_statement(NULL)");   // stored procedure, new (NULL = all accounts)
        READ_QUERIES.put("alerts",       "SELECT a.alert_ref, a.txn_ref, r.rule_name, a.severity, a.alert_status, c.full_name AS reviewed_by, a.reviewer_notes "
                                + "FROM fraud_alerts a JOIN detection_rules r ON a.rule_ref = r.rule_ref "
                                + "LEFT JOIN customers c ON a.reviewed_by = c.customer_number ORDER BY a.alert_ref DESC");
    }

    public static void main(String[] args) throws Exception {
        try (Connection c = DriverManager.getConnection(URL, USER, PASS)) {
            System.out.println("JDBC CONNECTION SUCCESSFUL -> " + URL);
        }
        HttpServer s = HttpServer.create(new InetSocketAddress("0.0.0.0", Integer.parseInt(env("PORT", "8080"))), 0);
        s.createContext("/", GuardServer::handleRequest);
        s.start();
        System.out.println("Open http://localhost:8080");
    }

    static void handleRequest(HttpExchange ex) throws IOException {
        String p = ex.getRequestURI().getPath();
        try {
            if (p.equals("/")) { send(ex, 200, "text/html; charset=utf-8", new String(Files.readAllBytes(Path.of("dashboard", "index.html")), StandardCharsets.UTF_8)); return; }
            if (!p.startsWith("/api/")) { send(ex, 404, "application/json", "{\"error\":\"not found\"}"); return; }
            Map<String, String> f = form(ex);
            try (Connection c = DriverManager.getConnection(URL, USER, PASS)) {
                String r = handleApi(c, ex.getRequestMethod(), p.substring(5), f);
                if (r == null) send(ex, 404, "application/json", "{\"error\":\"not found\"}");
                else send(ex, 200, "application/json", r);
            }
        } catch (Exception e) {
            send(ex, 400, "application/json", "{\"error\":\"" + esc(String.valueOf(e.getMessage())) + "\"}");
        }
    }

    static String handleApi(Connection c, String m, String p, Map<String, String> f) throws Exception {
        if (m.equals("GET")) {
            if (p.equals("summary")) return json(c, "SELECT (SELECT COUNT(*) FROM customers) AS customers, (SELECT COUNT(*) FROM bank_accounts) AS accounts, "
                + "(SELECT COUNT(*) FROM payment_transactions) AS transactions, (SELECT COUNT(*) FROM payment_transactions WHERE flagged='Yes') AS flagged_transactions, "
                + "(SELECT COUNT(*) FROM fraud_alerts WHERE alert_status='Open') AS open_alerts");
            if (READ_QUERIES.containsKey(p)) return json(c, READ_QUERIES.get(p));
            return null;
        }
        switch (p) {
            case "transactions": return checkTransaction(c, f);
            case "alerts/review": return reviewAlert(c, f);
            case "customers/add": {
                String id = nextId(c, "customers", "customer_number", "CUST-", 1000);
                update(c, "INSERT INTO customers (customer_number, full_name, email, access_level, joined_on, standing) VALUES (?,?,?,?,CURDATE(),'Active')",
                       id, f.get("name"), f.get("email"), f.get("level"));
                return "{\"ok\":true,\"customer\":\"" + id + "\"}";
            }
            case "customers/standing":
                update(c, "UPDATE customers SET standing=? WHERE customer_number=?", f.get("standing"), f.get("customer"));
                return "{\"ok\":true}";
            case "customers/delete":
                update(c, "DELETE FROM customers WHERE customer_number=?", f.get("customer"));   // FK error if the customer owns accounts
                return "{\"ok\":true}";
            default: return null;
        }
    }

    /** Insert a transaction, run every enabled rule against it, raise alerts + audit log, all in one DB transaction. */
    static String checkTransaction(Connection c, Map<String, String> f) throws Exception {
        String acc = f.get("account"), dev = f.get("device"), mer = f.get("merchant"), kind = f.get("kind");
        String loc = (f.get("location") == null || f.get("location").isBlank()) ? "Unknown" : f.get("location");
        BigDecimal amt = new BigDecimal(f.get("amount"));
        if (amt.signum() <= 0) throw new IllegalArgumentException("Amount must be positive");
        String owner   = scalar(c, "SELECT belongs_to FROM bank_accounts WHERE account_number=? AND status='Active'", acc);
        String trusted = scalar(c, "SELECT trusted FROM devices WHERE device_ref=?", dev);
        String risk    = scalar(c, "SELECT risk_level FROM merchants WHERE merchant_ref=?", mer);
        if (owner == null) throw new IllegalArgumentException("Account not found or not active");
        if (trusted == null || risk == null) throw new IllegalArgumentException("Unknown device or merchant");
        LocalDateTime dt = LocalDateTime.now();
        String hr = f.get("hour");
        if (hr != null && !hr.isBlank()) dt = dt.withHour(Integer.parseInt(hr));
        int h = dt.getHour();

        c.setAutoCommit(false);
        try {
            List<String> rules = new ArrayList<>();
            try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery("SELECT rule_ref FROM detection_rules WHERE enabled='Yes'")) {
                while (rs.next()) rules.add(rs.getString(1));
            }
            List<String[]> ruleHits = new ArrayList<>();
            for (String r : rules) {
                String sev = switch (r) {
                    case "RULE-6001" -> kind.equals("Withdrawal") && amt.compareTo(BigDecimal.valueOf(50000)) > 0 ? "High" : null;
                    case "RULE-6002" -> trusted.equals("No") ? "High" : null;
                    case "RULE-6003" -> (h >= 23 || h < 5) ? "Low" : null;
                    case "RULE-6004" -> risk.equals("High") ? "Medium" : null;
                    default -> null;
                };
                if (sev != null) ruleHits.add(new String[]{r, sev});
            }
            boolean clean = ruleHits.isEmpty();
            if (clean && update(c, "UPDATE bank_accounts SET balance = balance - ? WHERE account_number=? AND balance >= ?", amt, acc, amt) == 0)
                throw new IllegalArgumentException("Insufficient balance");

            String ref = nextId(c, "payment_transactions", "txn_ref", "TXN-", 3000);
            update(c, "INSERT INTO payment_transactions (txn_ref, from_account, device_ref, merchant_ref, kind, amount, currency, txn_datetime, location, status, flagged) VALUES (?,?,?,?,?,?,'INR',?,?,?,?)",
                   ref, acc, dev, mer, kind, amt, Timestamp.valueOf(dt), loc, clean ? "Completed" : "Under Review", clean ? "No" : "Yes");
            for (String[] hit : ruleHits)
                update(c, "INSERT INTO fraud_alerts (alert_ref, txn_ref, rule_ref, severity, alert_status) VALUES (?,?,?,?,'Open')",
                       nextId(c, "fraud_alerts", "alert_ref", "ALRT-", 7000), ref, hit[0], hit[1]);
            String ev = switch (kind) { case "Purchase" -> "Payment Made"; case "Transfer" -> "Transfer Sent"; default -> "Withdrawal Attempt"; };
            update(c, "INSERT INTO activity_log (log_ref, event_type, performed_by, account_number, txn_ref, event_time, details) VALUES (?,?,?,?,?,?,?)",
                   nextId(c, "activity_log", "log_ref", "LOG-", 8000), ev, owner, acc, ref, Timestamp.valueOf(dt), kind + " of INR " + amt + " to " + mer + " via " + dev);
            c.commit();
            return "{\"txn\":\"" + ref + "\",\"status\":\"" + (clean ? "Completed" : "Under Review") + "\",\"alerts\":" + ruleHits.size() + "}";
        } catch (Exception e) { c.rollback(); throw e; }
    }

    static String reviewAlert(Connection c, Map<String, String> f) throws SQLException {
        if (!"Administrator".equals(scalar(c, "SELECT access_level FROM customers WHERE customer_number=?", f.get("reviewer"))))
            throw new SQLException("Reviewer must be an Administrator");
        String txn = scalar(c, "SELECT txn_ref FROM fraud_alerts WHERE alert_ref=?", f.get("alert"));
        if (txn == null) throw new SQLException("Unknown alert");
        update(c, "UPDATE fraud_alerts SET alert_status=?, reviewed_by=?, reviewer_notes=? WHERE alert_ref=?",
               f.get("status"), f.get("reviewer"), f.get("notes"), f.get("alert"));
        if ("Confirmed Fraud".equals(f.get("status")))
            update(c, "UPDATE payment_transactions SET status='Blocked' WHERE txn_ref=?", txn);
        else
            update(c, "UPDATE payment_transactions SET status='Completed' WHERE txn_ref=? AND status='Under Review' "
                    + "AND NOT EXISTS (SELECT 1 FROM fraud_alerts WHERE txn_ref=? AND alert_status='Open')", txn, txn);
        return "{\"ok\":true}";
    }

    // ---------- helpers ----------
    static String nextId(Connection c, String table, String col, String prefix, int base) throws SQLException {
        return prefix + scalar(c, "SELECT COALESCE(MAX(CAST(SUBSTRING(" + col + "," + (prefix.length() + 1) + ") AS UNSIGNED)), " + base + ") + 1 FROM " + table);
    }
    static String scalar(Connection c, String sql, Object... a) throws SQLException {
        try (PreparedStatement ps = c.prepareStatement(sql)) {
            for (int i = 0; i < a.length; i++) ps.setObject(i + 1, a[i]);
            try (ResultSet rs = ps.executeQuery()) { return rs.next() ? rs.getString(1) : null; }
        }
    }
    static int update(Connection c, String sql, Object... a) throws SQLException {
        try (PreparedStatement ps = c.prepareStatement(sql)) {
            for (int i = 0; i < a.length; i++) ps.setObject(i + 1, a[i]);
            return ps.executeUpdate();
        }
    }
    static String json(Connection c, String sql) throws SQLException {
        try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery(sql)) {
            ResultSetMetaData md = rs.getMetaData();
            StringBuilder sb = new StringBuilder("[");
            boolean first = true;
            while (rs.next()) {
                if (!first) sb.append(','); first = false;
                sb.append('{');
                for (int i = 1; i <= md.getColumnCount(); i++) {
                    if (i > 1) sb.append(',');
                    Object v = rs.getObject(i);
                    sb.append('"').append(md.getColumnLabel(i)).append("\":");
                    if (v == null) sb.append("null");
                    else if (v instanceof Number) sb.append(v);
                    else sb.append('"').append(esc(v instanceof LocalDateTime ? v.toString().replace('T', ' ') : v.toString())).append('"');
                }
                sb.append('}');
            }
            return sb.append(']').toString();
        }
    }
    static String esc(String s) {
        StringBuilder b = new StringBuilder();
        for (char ch : s.toCharArray()) {
            if (ch == '"' || ch == '\\') b.append('\\').append(ch);
            else if (ch < 0x20) b.append(' ');
            else b.append(ch);
        }
        return b.toString();
    }
    static Map<String, String> form(HttpExchange ex) throws IOException {
        Map<String, String> m = new HashMap<>();
        if (!ex.getRequestMethod().equals("POST")) return m;
        String body = new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
        for (String kv : body.split("&")) {
            if (kv.isEmpty()) continue;
            String[] x = kv.split("=", 2);
            m.put(URLDecoder.decode(x[0], StandardCharsets.UTF_8), x.length > 1 ? URLDecoder.decode(x[1], StandardCharsets.UTF_8) : "");
        }
        return m;
    }
    static void send(HttpExchange ex, int code, String type, String body) throws IOException {
        byte[] b = body.getBytes(StandardCharsets.UTF_8);
        ex.getResponseHeaders().set("Content-Type", type);
        ex.sendResponseHeaders(code, b.length);
        try (OutputStream o = ex.getResponseBody()) { o.write(b); }
    }
}
