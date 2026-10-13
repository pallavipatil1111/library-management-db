-- =====================================================================
-- Business rules as stored procedures.
-- Dates are passed in so the procedures can be tested and seeded with
-- history; pass NULL to use today's date.
-- =====================================================================
USE library;

DROP PROCEDURE IF EXISTS sp_issue_book;
DROP PROCEDURE IF EXISTS sp_return_book;
DROP PROCEDURE IF EXISTS sp_pay_fines;

DELIMITER //

-- Lend one available copy of a book to a member.
-- Fails with a clear message if the member is inactive, has too many books,
-- owes too much in fines, or no copy is available.
CREATE PROCEDURE sp_issue_book(IN p_member_id INT, IN p_book_id INT, IN p_issue_date DATE)
BEGIN
    DECLARE v_issue_date DATE;
    DECLARE v_active TINYINT;
    DECLARE v_type VARCHAR(10);
    DECLARE v_max_loans TINYINT;
    DECLARE v_loan_days TINYINT;
    DECLARE v_open_loans INT;
    DECLARE v_fines_blocked TINYINT;
    DECLARE v_copy_id INT;
    DECLARE v_due_date DATE;

    SET v_issue_date = COALESCE(p_issue_date, CURDATE());

    -- aggregates always return one row, so a missing member gives NULLs
    -- instead of leaving the variables untouched
    SELECT MAX(m.is_active), MAX(m.member_type), MAX(r.max_loans), MAX(r.loan_days),
           MAX(DATE_ADD(v_issue_date, INTERVAL r.loan_days DAY))
      INTO v_active, v_type, v_max_loans, v_loan_days, v_due_date
      FROM members m JOIN membership_rules r ON r.member_type = m.member_type
     WHERE m.member_id = p_member_id;

    IF v_type IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Member not found';
    END IF;
    IF v_active = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Member account is inactive';
    END IF;

    SELECT COUNT(*) INTO v_open_loans FROM loans WHERE member_id = p_member_id AND returned_on IS NULL;
    IF v_open_loans >= v_max_loans THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Member has reached the borrowing limit';
    END IF;

    -- compare in SQL (exact DECIMAL arithmetic) rather than in procedure variables
    SET @chk_member = p_member_id;
    SELECT CASE WHEN COALESCE(SUM(f.amount), 0) >=
                     (SELECT r.fine_block_limit
                        FROM members m JOIN membership_rules r ON r.member_type = m.member_type
                       WHERE m.member_id = @chk_member)
                THEN 1 ELSE 0 END
      INTO v_fines_blocked
      FROM fines f JOIN loans l ON l.loan_id = f.loan_id
     WHERE l.member_id = @chk_member AND f.is_paid = 0;
    IF v_fines_blocked = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Member has unpaid fines above the limit';
    END IF;

    START TRANSACTION;
        -- lock the chosen copy so two librarians can't lend the same one
        SELECT MIN(copy_id) INTO v_copy_id
          FROM copies
         WHERE book_id = p_book_id AND status = 'available'
         FOR UPDATE;

        IF v_copy_id IS NULL THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No copy of this book is available';
        END IF;

        -- the AFTER INSERT trigger marks the copy as on_loan
        INSERT INTO loans (copy_id, member_id, issued_on, due_on)
        VALUES (v_copy_id, p_member_id, v_issue_date, v_due_date);
    COMMIT;

    SELECT LAST_INSERT_ID() AS loan_id, v_copy_id AS copy_id, v_due_date AS due_on;
END//

-- Return a copy. The AFTER UPDATE trigger frees the copy and records any late fine.
CREATE PROCEDURE sp_return_book(IN p_copy_id INT, IN p_return_date DATE)
BEGIN
    DECLARE v_loan_id INT;
    DECLARE v_return_date DATE;
    SET v_return_date = COALESCE(p_return_date, CURDATE());

    SELECT MAX(loan_id) INTO v_loan_id
      FROM loans
     WHERE copy_id = p_copy_id AND returned_on IS NULL;

    IF v_loan_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This copy is not on loan';
    END IF;

    -- session variables keep this UPDATE portable to MySQL-compatible engines
    -- that don't expose procedure variables to statements that fire triggers
    SET @ret_date = v_return_date;
    SET @ret_loan = v_loan_id;
    UPDATE loans SET returned_on = @ret_date WHERE loan_id = @ret_loan;

    SELECT l.loan_id, l.returned_on, COALESCE(f.days_late, 0) AS days_late, COALESCE(f.amount, 0) AS fine
      FROM loans l LEFT JOIN fines f ON f.loan_id = l.loan_id
     WHERE l.loan_id = v_loan_id;
END//

-- Mark all of a member's unpaid fines as paid.
CREATE PROCEDURE sp_pay_fines(IN p_member_id INT, IN p_paid_date DATE)
BEGIN
    SET @pay_date = COALESCE(p_paid_date, CURDATE());
    SET @pay_member = p_member_id;
    UPDATE fines f JOIN loans l ON l.loan_id = f.loan_id
       SET f.is_paid = 1, f.paid_on = @pay_date
     WHERE l.member_id = @pay_member AND f.is_paid = 0;
END//
DELIMITER ;

SELECT 'Procedures created' AS status;
