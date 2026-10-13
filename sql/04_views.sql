-- =====================================================================
-- Reporting views
-- =====================================================================
USE library;

-- How many copies of each book exist and how many are on the shelf now
CREATE OR REPLACE VIEW v_book_availability AS
SELECT
    b.book_id,
    b.title,
    b.category,
    COUNT(c.copy_id)                                       AS total_copies,
    SUM(CASE WHEN c.status = 'available' THEN 1 ELSE 0 END) AS available_copies
FROM books b
LEFT JOIN copies c ON c.book_id = b.book_id
GROUP BY b.book_id, b.title, b.category;

-- Loans still out past their due date (as of today)
CREATE OR REPLACE VIEW v_overdue_loans AS
SELECT
    l.loan_id,
    m.full_name                       AS member,
    m.email,
    b.title,
    l.issued_on,
    l.due_on,
    DATEDIFF(CURDATE(), l.due_on)     AS days_overdue
FROM loans l
JOIN members m ON m.member_id = l.member_id
JOIN copies c  ON c.copy_id   = l.copy_id
JOIN books b   ON b.book_id   = c.book_id
WHERE l.returned_on IS NULL AND l.due_on < CURDATE();

-- Most borrowed books, ranked within their category
CREATE OR REPLACE VIEW v_popular_books AS
SELECT
    b.title,
    b.category,
    COUNT(l.loan_id)                                                     AS times_borrowed,
    RANK() OVER (PARTITION BY b.category ORDER BY COUNT(l.loan_id) DESC) AS rank_in_category
FROM books b
JOIN copies c ON c.book_id = b.book_id
JOIN loans l  ON l.copy_id = c.copy_id
GROUP BY b.book_id, b.title, b.category;

-- One row per member: activity, books out and money owed
CREATE OR REPLACE VIEW v_member_summary AS
SELECT
    m.member_id,
    m.full_name,
    m.member_type,
    COUNT(DISTINCT l.loan_id)                                             AS total_loans,
    COUNT(DISTINCT CASE WHEN l.returned_on IS NULL THEN l.loan_id END)    AS books_out,
    COALESCE(SUM(CASE WHEN f.is_paid = 0 THEN f.amount END), 0)           AS unpaid_fines
FROM members m
LEFT JOIN loans l ON l.member_id = m.member_id
LEFT JOIN fines f ON f.loan_id   = l.loan_id
GROUP BY m.member_id, m.full_name, m.member_type;
