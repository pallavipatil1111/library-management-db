"""Automated tests for the library database's procedures, triggers, constraints and views.

Each test rebuilds the database from sql/ and tests/fixtures.sql, runs some SQL through the
command-line client, and checks the result. Only the Python standard library is used.

    DB_ENGINE=mysql MYSQL_HOST=127.0.0.1 MYSQL_USER=root MYSQL_PASSWORD=root python tests/run_tests.py
    DB_ENGINE=dolt  DOLT_DIR=/tmp/libtest python tests/run_tests.py     # Dolt, a MySQL-compatible engine
"""
import csv
import io
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_FILES = sorted((ROOT / "sql").glob("0*.sql"))
FIXTURES = ROOT / "tests" / "fixtures.sql"
ENGINE = os.environ.get("DB_ENGINE", "mysql")


class SqlError(Exception):
    pass


def _cmd():
    if ENGINE == "dolt":
        return ["dolt", "--data-dir", os.environ.get("DOLT_DIR", "/tmp/library-test"), "sql", "-r", "csv"]
    env_pw = os.environ.get("MYSQL_PASSWORD", "")
    cmd = ["mysql", "-h", os.environ.get("MYSQL_HOST", "127.0.0.1"), "-u", os.environ.get("MYSQL_USER", "root"),
           "--batch", "--skip-column-names"]
    if env_pw:
        os.environ["MYSQL_PWD"] = env_pw
    return cmd


def run(sql: str) -> str:
    proc = subprocess.run(_cmd(), input=sql, text=True, capture_output=True)
    if proc.returncode != 0 or "error" in proc.stderr.lower():
        raise SqlError((proc.stderr or proc.stdout).strip())
    return proc.stdout


def query(sql: str) -> list[list[str]]:
    """Run a single SELECT against the library database and return its rows as strings."""
    out = run("USE library;\n" + sql)
    if ENGINE == "dolt":
        rows = list(csv.reader(io.StringIO(out)))
        return rows[1:]  # drop header
    return [line.split("\t") for line in out.splitlines() if line]


def scalar(sql: str) -> str:
    rows = query(sql)
    return rows[0][0] if rows else None


def reset():
    if ENGINE == "dolt":
        d = os.environ.get("DOLT_DIR", "/tmp/library-test")
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
    for f in SCHEMA_FILES:
        run(f.read_text())
    run(FIXTURES.read_text())


def expect_error(sql: str, message: str):
    try:
        run("USE library;\n" + sql)
    except SqlError as e:
        assert message.lower() in str(e).lower(), f"expected error containing {message!r}, got {e}"
        return
    raise AssertionError(f"expected an error containing {message!r}, but the SQL succeeded")


def _same(a, b):
    try:
        return abs(float(a) - float(b)) < 1e-9
    except (TypeError, ValueError):
        return str(a) == str(b)


def eq(actual, expected, what):
    if isinstance(expected, list):
        ok = isinstance(actual, list) and len(actual) == len(expected) and all(map(_same, actual, expected))
    else:
        ok = _same(actual, expected)
    assert ok, f"{what}: expected {expected!r}, got {actual!r}"


# ------------------------------------------------------------------ tests
def test_issue_marks_copy_on_loan_and_sets_due_date():
    run("USE library; CALL sp_issue_book(1, 1, '2026-01-01');")
    eq(scalar("SELECT status FROM copies WHERE copy_id = 1"), "on_loan", "copy status")
    eq(scalar("SELECT due_on FROM loans WHERE member_id = 1"), "2026-01-15", "student due date (14 days)")


def test_staff_get_longer_loans():
    run("USE library; CALL sp_issue_book(2, 2, '2026-01-01');")
    eq(scalar("SELECT due_on FROM loans WHERE member_id = 2"), "2026-01-31", "staff due date (30 days)")


def test_issue_picks_the_next_free_copy():
    run("USE library; CALL sp_issue_book(1, 2, '2026-01-01'); CALL sp_issue_book(2, 2, '2026-01-01');")
    eq(scalar("SELECT GROUP_CONCAT(copy_id ORDER BY copy_id) FROM loans"), "2,3", "copies lent")


def test_issue_fails_when_no_copy_is_available():
    run("USE library; CALL sp_issue_book(1, 1, '2026-01-01');")
    expect_error("CALL sp_issue_book(2, 1, '2026-01-02');", "No copy of this book is available")
    eq(scalar("SELECT COUNT(*) FROM loans"), 1, "loans after failed issue")


def test_inactive_member_cannot_borrow():
    expect_error("CALL sp_issue_book(3, 2, '2026-01-01');", "Member account is inactive")


def test_unknown_member_cannot_borrow():
    expect_error("CALL sp_issue_book(999, 2, '2026-01-01');", "Member not found")


def test_borrowing_limit_is_enforced():
    run("USE library; CALL sp_issue_book(1, 1, '2026-01-01'); CALL sp_issue_book(1, 2, '2026-01-01');"
        " CALL sp_issue_book(1, 3, '2026-01-01');")
    expect_error("CALL sp_issue_book(1, 4, '2026-01-01');", "borrowing limit")


def test_on_time_return_frees_copy_without_fine():
    run("USE library; CALL sp_issue_book(1, 1, '2026-01-01'); CALL sp_return_book(1, '2026-01-10');")
    eq(scalar("SELECT status FROM copies WHERE copy_id = 1"), "available", "copy status after return")
    eq(scalar("SELECT COUNT(*) FROM fines"), 0, "fines")


def test_late_return_creates_fine_at_student_rate():
    run("USE library; CALL sp_issue_book(1, 1, '2026-01-01'); CALL sp_return_book(1, '2026-01-25');")
    eq(query("SELECT days_late, amount FROM fines")[0], ["10", "50.00"], "fine for 10 days late at 5/day")


def test_late_return_creates_fine_at_staff_rate():
    run("USE library; CALL sp_issue_book(2, 1, '2026-01-01'); CALL sp_return_book(1, '2026-02-05');")
    eq(query("SELECT days_late, amount FROM fines")[0], ["5", "10.00"], "fine for 5 days late at 2/day")


def test_unpaid_fines_block_new_loans_until_paid():
    run("USE library; CALL sp_issue_book(1, 1, '2026-01-01'); CALL sp_return_book(1, '2026-02-04');")  # 20 days -> 100
    expect_error("CALL sp_issue_book(1, 2, '2026-02-05');", "unpaid fines")
    run("USE library; CALL sp_pay_fines(1, '2026-02-05');")
    eq(query("SELECT is_paid, paid_on FROM fines")[0], ["1", "2026-02-05"], "fine marked paid")
    run("USE library; CALL sp_issue_book(1, 2, '2026-02-05');")
    eq(scalar("SELECT COUNT(*) FROM loans WHERE returned_on IS NULL"), 1, "open loans after paying")


def test_returning_a_copy_that_is_not_on_loan_fails():
    expect_error("CALL sp_return_book(2, '2026-01-01');", "not on loan")


def test_member_with_books_out_cannot_be_deactivated():
    run("USE library; CALL sp_issue_book(1, 1, '2026-01-01');")
    expect_error("UPDATE members SET is_active = 0 WHERE member_id = 1;", "Return all books")
    run("USE library; CALL sp_return_book(1, '2026-01-05'); UPDATE members SET is_active = 0 WHERE member_id = 1;")
    eq(scalar("SELECT is_active FROM members WHERE member_id = 1"), 0, "deactivated after return")


def test_constraints_reject_bad_data():
    expect_error("INSERT INTO loans (copy_id, member_id, issued_on, due_on) VALUES (2, 1, '2026-01-10', '2026-01-01');", "")
    expect_error("INSERT INTO members (full_name, email, member_type, joined_on) VALUES ('X', 's1@test.example', 'student', '2026-01-01');", "")
    expect_error("INSERT INTO copies (book_id, shelf, acquired_on) VALUES (999, 'X', '2026-01-01');", "")


def test_views_report_availability_and_member_summary():
    run("USE library; CALL sp_issue_book(1, 2, '2026-01-01'); CALL sp_issue_book(1, 1, '2026-01-01');"
        " CALL sp_return_book(1, '2026-01-30');")
    eq(query("SELECT total_copies, available_copies FROM v_book_availability WHERE book_id = 2")[0], ["2", "1"],
       "availability of book 2")
    eq(query("SELECT total_loans, books_out, unpaid_fines FROM v_member_summary WHERE member_id = 1")[0],
       ["2", "1", "75.00"], "member 1 summary")
    eq(scalar("SELECT COUNT(*) FROM v_overdue_loans"), 1, "overdue loans (book 2 is still out past its due date)")


TESTS = [v for k, v in list(globals().items()) if k.startswith("test_")]


def main():
    failed = 0
    for t in TESTS:
        name = t.__name__[5:].replace("_", " ")
        try:
            reset()
            t()
            print(f"  PASS  {name}")
        except (AssertionError, SqlError) as e:
            failed += 1
            print(f"  FAIL  {name}\n        {e}")
    print(f"\n{len(TESTS) - failed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
