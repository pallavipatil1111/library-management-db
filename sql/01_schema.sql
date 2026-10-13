-- =====================================================================
-- Library Management Database — schema (MySQL 8)
-- Normalised to 3NF: every non-key column depends only on its table's key.
-- =====================================================================
CREATE DATABASE IF NOT EXISTS library;
USE library;

DROP TABLE IF EXISTS fines;
DROP TABLE IF EXISTS loans;
DROP TABLE IF EXISTS copies;
DROP TABLE IF EXISTS book_authors;
DROP TABLE IF EXISTS books;
DROP TABLE IF EXISTS authors;
DROP TABLE IF EXISTS publishers;
DROP TABLE IF EXISTS members;
DROP TABLE IF EXISTS membership_rules;

-- Borrowing rules per member type, kept as data so they can change without code changes
CREATE TABLE membership_rules (
    member_type      VARCHAR(10)   PRIMARY KEY,
    max_loans        TINYINT       NOT NULL CHECK (max_loans > 0),
    loan_days        TINYINT       NOT NULL CHECK (loan_days > 0),
    fine_per_day     DECIMAL(6,2)  NOT NULL CHECK (fine_per_day >= 0),
    fine_block_limit DECIMAL(8,2)  NOT NULL   -- unpaid fines at or above this block new loans
);

CREATE TABLE members (
    member_id    INT           PRIMARY KEY AUTO_INCREMENT,
    full_name    VARCHAR(80)   NOT NULL,
    email        VARCHAR(120)  NOT NULL UNIQUE,
    member_type  VARCHAR(10)   NOT NULL,
    joined_on    DATE          NOT NULL,
    is_active    TINYINT(1)    NOT NULL DEFAULT 1,
    CONSTRAINT fk_member_type FOREIGN KEY (member_type) REFERENCES membership_rules(member_type)
);

CREATE TABLE publishers (
    publisher_id INT          PRIMARY KEY AUTO_INCREMENT,
    name         VARCHAR(80)  NOT NULL UNIQUE
);

CREATE TABLE authors (
    author_id INT          PRIMARY KEY AUTO_INCREMENT,
    full_name VARCHAR(80)  NOT NULL,
    country   VARCHAR(40)
);

CREATE TABLE books (
    book_id        INT           PRIMARY KEY AUTO_INCREMENT,
    isbn           CHAR(13)      NOT NULL UNIQUE,
    title          VARCHAR(150)  NOT NULL,
    category       VARCHAR(40)   NOT NULL,
    publisher_id   INT           NOT NULL,
    published_year SMALLINT      NOT NULL CHECK (published_year BETWEEN 1800 AND 2100),
    CONSTRAINT fk_book_publisher FOREIGN KEY (publisher_id) REFERENCES publishers(publisher_id)
);

-- Many-to-many: a book can have several authors and an author several books
CREATE TABLE book_authors (
    book_id   INT NOT NULL,
    author_id INT NOT NULL,
    PRIMARY KEY (book_id, author_id),
    CONSTRAINT fk_ba_book   FOREIGN KEY (book_id)   REFERENCES books(book_id),
    CONSTRAINT fk_ba_author FOREIGN KEY (author_id) REFERENCES authors(author_id)
);

-- A physical copy of a book on the shelf
CREATE TABLE copies (
    copy_id        INT          PRIMARY KEY AUTO_INCREMENT,
    book_id        INT          NOT NULL,
    shelf          VARCHAR(10)  NOT NULL,
    status         ENUM('available', 'on_loan', 'lost', 'repair') NOT NULL DEFAULT 'available',
    acquired_on    DATE         NOT NULL,
    CONSTRAINT fk_copy_book FOREIGN KEY (book_id) REFERENCES books(book_id)
);

CREATE TABLE loans (
    loan_id     INT   PRIMARY KEY AUTO_INCREMENT,
    copy_id     INT   NOT NULL,
    member_id   INT   NOT NULL,
    issued_on   DATE  NOT NULL,
    due_on      DATE  NOT NULL,
    returned_on DATE  NULL,
    CONSTRAINT fk_loan_copy   FOREIGN KEY (copy_id)   REFERENCES copies(copy_id),
    CONSTRAINT fk_loan_member FOREIGN KEY (member_id) REFERENCES members(member_id),
    CONSTRAINT chk_due_after_issue CHECK (due_on > issued_on),
    CONSTRAINT chk_return_after_issue CHECK (returned_on IS NULL OR returned_on >= issued_on)
);

CREATE TABLE fines (
    fine_id    INT           PRIMARY KEY AUTO_INCREMENT,
    loan_id    INT           NOT NULL UNIQUE,          -- at most one fine per loan
    days_late  SMALLINT      NOT NULL CHECK (days_late > 0),
    amount     DECIMAL(8,2)  NOT NULL CHECK (amount >= 0),
    is_paid    TINYINT(1)    NOT NULL DEFAULT 0,
    paid_on    DATE          NULL,
    CONSTRAINT fk_fine_loan FOREIGN KEY (loan_id) REFERENCES loans(loan_id)
);
