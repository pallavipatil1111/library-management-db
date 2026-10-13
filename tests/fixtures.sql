-- Small, known dataset for the automated tests (loaded after the schema).
USE library;
INSERT INTO membership_rules VALUES ('student', 3, 14, 5.00, 100.00), ('staff', 5, 30, 2.00, 200.00);
INSERT INTO publishers (publisher_id, name) VALUES (1, 'Test Press');
INSERT INTO authors (author_id, full_name, country) VALUES (1, 'Asha Rao', 'India'), (2, 'Vik Menon', 'India');
INSERT INTO books (book_id, isbn, title, category, publisher_id, published_year) VALUES
  (1, '9780000000001', 'Databases',          'Computer Science', 1, 2020),
  (2, '9780000000002', 'Algorithms',         'Computer Science', 1, 2019),
  (3, '9780000000003', 'Operating Systems',  'Computer Science', 1, 2018),
  (4, '9780000000004', 'Computer Networks',  'Computer Science', 1, 2021);
INSERT INTO book_authors VALUES (1, 1), (2, 1), (2, 2), (3, 2), (4, 1);
-- book 1 has ONE copy; the others have two
INSERT INTO copies (copy_id, book_id, shelf, acquired_on) VALUES
  (1, 1, 'CS-01', '2024-01-01'),
  (2, 2, 'CS-02', '2024-01-01'), (3, 2, 'CS-02', '2024-01-01'),
  (4, 3, 'CS-03', '2024-01-01'), (5, 3, 'CS-03', '2024-01-01'),
  (6, 4, 'CS-04', '2024-01-01'), (7, 4, 'CS-04', '2024-01-01');
INSERT INTO members (member_id, full_name, email, member_type, joined_on, is_active) VALUES
  (1, 'Student One', 's1@test.example', 'student', '2025-01-01', 1),
  (2, 'Staff Two',   's2@test.example', 'staff',   '2025-01-01', 1),
  (3, 'Inactive Three', 's3@test.example', 'student', '2025-01-01', 0);
