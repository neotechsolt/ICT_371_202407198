DROP TABLE IF EXISTS book_loans;
DROP TABLE IF EXISTS books;

-- 1. Tables and sample data
CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);
 
CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    loan_status    VARCHAR(10) NOT NULL DEFAULT 'BORROWED'
                   CHECK (loan_status IN ('BORROWED','RETURNED'))
);
 
INSERT INTO books (title, available_copies) VALUES
 ('Database Systems', 8),
 ('Discrete Mathematics', 2),
 ('Operating Systems', 0);
 
-- 2. IF / ELSIF / ELSE
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT title, available_copies FROM books ORDER BY book_id LOOP
        IF r.available_copies = 0 THEN
            RAISE NOTICE '%: UNAVAILABLE (% copies)', r.title, r.available_copies;
        ELSIF r.available_copies <= 3 THEN
            RAISE NOTICE '%: LOW on copies (% left)', r.title, r.available_copies;
        ELSE
            RAISE NOTICE '%: sufficiently stocked (% copies)', r.title, r.available_copies;
        END IF;
    END LOOP;
END $$;
 
-- 3. WHILE and numeric FOR
DO $$
DECLARE
    n INT := 1;
BEGIN
    WHILE n <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number %', n;
        n := n + 1;
    END LOOP;
 
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', i;
    END LOOP;
END $$;
 
-- 4. borrow_book procedure
CREATE OR REPLACE PROCEDURE borrow_book(p_book_id INT, p_student VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_qty;
    END IF;
 
    SELECT available_copies INTO v_available
    FROM books WHERE book_id = p_book_id FOR UPDATE;
 
    IF NOT FOUND THEN
        RAISE NOTICE 'Book % does not exist. Loan not recorded.', p_book_id;
        RETURN;
    END IF;
 
    IF v_available < p_qty THEN
        RAISE NOTICE 'Loan REJECTED for %: requested %, only % available.', p_student, p_qty, v_available;
        RETURN;
    END IF;
 
    UPDATE books SET available_copies = available_copies - p_qty WHERE book_id = p_book_id;
    INSERT INTO book_loans (book_id, student_number, quantity) VALUES (p_book_id, p_student, p_qty);
    RAISE NOTICE 'Loan recorded for %: % copy(ies) of book %.', p_student, p_qty, p_book_id;
END $$;
 
-- 5. Two valid loans and one exceeding request
CALL borrow_book(1, '2024001', 3);   
CALL borrow_book(2, '2024002', 1);   
CALL borrow_book(2, '2024003', 5);   
 
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
 
-- 6. return_book procedure
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book   INT;
    v_qty    INT;
    v_status VARCHAR;
BEGIN
    SELECT book_id, quantity, loan_status INTO v_book, v_qty, v_status
    FROM book_loans WHERE loan_id = p_loan_id FOR UPDATE;
 
    IF NOT FOUND THEN
        RAISE NOTICE 'Loan % not found.', p_loan_id;
        RETURN;
    END IF;
 
    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % already returned. No copies restored.', p_loan_id;
        RETURN;
    END IF;
 
    UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;
    UPDATE books SET available_copies = available_copies + v_qty WHERE book_id = v_book;
    RAISE NOTICE 'Loan % returned. % copy(ies) restored.', p_loan_id, v_qty;
END $$;
 
CALL return_book(1);   
CALL return_book(1);   
 
SELECT * FROM books ORDER BY book_id;
 
-- 7. Explicit cursor: books with few copies remaining
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT title, available_copies FROM books
        WHERE available_copies <= 3 ORDER BY available_copies;
    v_title  books.title%TYPE;
    v_copies books.available_copies%TYPE;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_title, v_copies;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few copies remaining: % (% left)', v_title, v_copies;
    END LOOP;
    CLOSE cur_low;
END $$;
 
-- 8. Zero copies: handled with EXCEPTION block
DO $$
BEGIN
    CALL borrow_book(1, '2024004', 0);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;
 
-- 9. Final results
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;