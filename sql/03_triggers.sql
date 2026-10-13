-- =====================================================================
-- Triggers keep copy status and fines consistent automatically.
-- =====================================================================
USE library;

DROP TRIGGER IF EXISTS trg_loans_after_insert;
DROP TRIGGER IF EXISTS trg_loans_after_update;
DROP TRIGGER IF EXISTS trg_members_before_update;

DELIMITER //

-- A new open loan puts the copy on loan
CREATE TRIGGER trg_loans_after_insert
AFTER INSERT ON loans
FOR EACH ROW
BEGIN
    IF NEW.returned_on IS NULL THEN
        UPDATE copies SET status = 'on_loan' WHERE copy_id = NEW.copy_id;
    END IF;
END//

-- Returning a loan frees the copy and, if it's late, records a fine
CREATE TRIGGER trg_loans_after_update
AFTER UPDATE ON loans
FOR EACH ROW
BEGIN
    DECLARE v_rate DECIMAL(6,2);
    DECLARE v_days INT;

    IF OLD.returned_on IS NULL AND NEW.returned_on IS NOT NULL THEN
        UPDATE copies SET status = 'available' WHERE copy_id = NEW.copy_id;

        SET v_days = DATEDIFF(NEW.returned_on, NEW.due_on);
        IF v_days > 0 THEN
            SELECT r.fine_per_day INTO v_rate
              FROM members m JOIN membership_rules r ON r.member_type = m.member_type
             WHERE m.member_id = NEW.member_id;
            INSERT INTO fines (loan_id, days_late, amount) VALUES (NEW.loan_id, v_days, v_days * v_rate);
        END IF;
    END IF;
END//

-- A member with books still out can't be deactivated
CREATE TRIGGER trg_members_before_update
BEFORE UPDATE ON members
FOR EACH ROW
BEGIN
    IF OLD.is_active = 1 AND NEW.is_active = 0 AND
       (SELECT COUNT(*) FROM loans WHERE member_id = OLD.member_id AND returned_on IS NULL) > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Return all books before deactivating this member';
    END IF;
END//
DELIMITER ;

SELECT 'Triggers created' AS status;
