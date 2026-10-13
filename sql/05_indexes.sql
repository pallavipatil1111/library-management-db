-- =====================================================================
-- Indexes for the most common lookups. InnoDB already indexes primary,
-- unique and foreign keys; these cover the remaining hot paths.
-- =====================================================================
USE library;

-- "Is a copy of this book available?" (sp_issue_book)
CREATE INDEX idx_copies_book_status ON copies (book_id, status);
-- "How many books does this member have out?" (sp_issue_book, v_member_summary)
CREATE INDEX idx_loans_member_open  ON loans (member_id, returned_on);
-- "Which loans are overdue?" (v_overdue_loans)
CREATE INDEX idx_loans_due_open     ON loans (returned_on, due_on);
-- title search
CREATE INDEX idx_books_title        ON books (title);
