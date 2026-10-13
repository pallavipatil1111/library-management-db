-- =====================================================================
-- Example reports a librarian would run
-- =====================================================================
USE library;

-- R1. Headline numbers
SELECT
    (SELECT COUNT(*) FROM books)                                   AS titles,
    (SELECT COUNT(*) FROM copies)                                  AS copies,
    (SELECT COUNT(*) FROM members WHERE is_active = 1)             AS active_members,
    (SELECT COUNT(*) FROM loans)                                   AS total_loans,
    (SELECT COUNT(*) FROM loans WHERE returned_on IS NULL)         AS books_out_now,
    (SELECT ROUND(100 * AVG(returned_on <= due_on), 1)
       FROM loans WHERE returned_on IS NOT NULL)                   AS on_time_return_pct;

-- R2. Top 3 most borrowed titles in each category
SELECT category, rank_in_category, title, times_borrowed
FROM v_popular_books
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;

-- R3. Loans per month, with the share returned late
SELECT
    DATE_FORMAT(issued_on, '%Y-%m')                                        AS month_issued,
    COUNT(*)                                                               AS loans,
    ROUND(100 * AVG(CASE WHEN returned_on > due_on THEN 1 ELSE 0 END), 1)  AS late_pct
FROM loans
GROUP BY DATE_FORMAT(issued_on, '%Y-%m')
ORDER BY month_issued;

-- R4. Fines collected and outstanding, by member type
SELECT
    m.member_type,
    COUNT(f.fine_id)                                        AS fines,
    SUM(CASE WHEN f.is_paid = 1 THEN f.amount ELSE 0 END)   AS collected,
    SUM(CASE WHEN f.is_paid = 0 THEN f.amount ELSE 0 END)   AS outstanding,
    ROUND(AVG(f.days_late), 1)                              AS avg_days_late
FROM fines f
JOIN loans l   ON l.loan_id   = f.loan_id
JOIN members m ON m.member_id = l.member_id
GROUP BY m.member_type;

-- R5. Titles that are always out: no copy on the shelf right now
SELECT title, category, total_copies
FROM v_book_availability
WHERE available_copies = 0
ORDER BY total_copies DESC, title;
