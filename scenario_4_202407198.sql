DROP TABLE IF EXISTS dispensing_records;
DROP TABLE IF EXISTS medicines;
 
-- 1. Tables and sample data
CREATE TABLE medicines (
    medicine_id    SERIAL PRIMARY KEY,
    medicine_name  VARCHAR(80) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);
 
CREATE TABLE dispensing_records (
    record_id      SERIAL PRIMARY KEY,
    medicine_id    INT NOT NULL REFERENCES medicines(medicine_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    status         VARCHAR(10) NOT NULL DEFAULT 'DISPENSED'
                   CHECK (status IN ('DISPENSED','REVERSED'))
);
 
INSERT INTO medicines (medicine_name, stock_quantity) VALUES
 ('Paracetamol 500mg', 100),
 ('Amoxicillin 250mg', 15),
 ('Oral Rehydration Salts', 0);
 
-- 2. IF / ELSIF / ELSE
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT medicine_name, stock_quantity FROM medicines ORDER BY medicine_id LOOP
        IF r.stock_quantity = 0 THEN
            RAISE NOTICE '%: OUT OF STOCK', r.medicine_name;
        ELSIF r.stock_quantity < 20 THEN
            RAISE NOTICE '%: LOW stock (%)', r.medicine_name, r.stock_quantity;
        ELSE
            RAISE NOTICE '%: sufficiently stocked (%)', r.medicine_name, r.stock_quantity;
        END IF;
    END LOOP;
END $$;
 
-- 3. WHILE and numeric FOR
DO $$
DECLARE
    d INT := 1;
BEGIN
    WHILE d <= 3 LOOP
        RAISE NOTICE 'Stock review day %', d;
        d := d + 1;
    END LOOP;
 
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection %', i;
    END LOOP;
END $$;
 
-- 4. dispense_medicine procedure
CREATE OR REPLACE PROCEDURE dispense_medicine(p_medicine_id INT, p_student VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid dispensing quantity: % (must be greater than zero)', p_qty;
    END IF;
 
    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;
 
    IF NOT FOUND THEN
        RAISE NOTICE 'Medicine % does not exist.', p_medicine_id;
        RETURN;
    END IF;
 
    IF v_stock < p_qty THEN
        RAISE NOTICE 'Dispensing REJECTED for %: requested %, only % in stock.', p_student, p_qty, v_stock;
        RETURN;
    END IF;
 
    UPDATE medicines SET stock_quantity = stock_quantity - p_qty WHERE medicine_id = p_medicine_id;
    INSERT INTO dispensing_records (medicine_id, student_number, quantity)
    VALUES (p_medicine_id, p_student, p_qty);
    RAISE NOTICE 'Dispensed % unit(s) of medicine % to %.', p_qty, p_medicine_id, p_student;
END $$;
 
-- 5. Two valid quantities and one exceeding stock
CALL dispense_medicine(1, '2024001', 10); 
CALL dispense_medicine(2, '2024002', 5);    
CALL dispense_medicine(2, '2024003', 50);   
 
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;
 
-- 6. reverse_dispensing procedure
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine INT;
    v_qty      INT;
    v_status   VARCHAR;
BEGIN
    SELECT medicine_id, quantity, status INTO v_medicine, v_qty, v_status
    FROM dispensing_records WHERE record_id = p_record_id FOR UPDATE;
 
    IF NOT FOUND THEN
        RAISE NOTICE 'Dispensing record % not found.', p_record_id;
        RETURN;
    END IF;
 
    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % already reversed. Stock not restored again.', p_record_id;
        RETURN;
    END IF;
 
    UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
    UPDATE medicines SET stock_quantity = stock_quantity + v_qty WHERE medicine_id = v_medicine;
    RAISE NOTICE 'Record % reversed. % unit(s) restored to stock.', p_record_id, v_qty;
END $$;
 
CALL reverse_dispensing(1);   
CALL reverse_dispensing(1);   
 
SELECT * FROM medicines ORDER BY medicine_id;
 
-- 7. Explicit cursor: medicines below a low-stock threshold
DO $$
DECLARE
    v_threshold CONSTANT INT := 20;
    cur_low CURSOR (p_limit INT) FOR
        SELECT medicine_name, stock_quantity FROM medicines
        WHERE stock_quantity < p_limit ORDER BY stock_quantity;
    v_name  medicines.medicine_name%TYPE;
    v_stock medicines.stock_quantity%TYPE;
BEGIN
    OPEN cur_low(v_threshold);
    LOOP
        FETCH cur_low INTO v_name, v_stock;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Below threshold (%): % has % unit(s)', v_threshold, v_name, v_stock;
    END LOOP;
    CLOSE cur_low;
END $$;
 
-- 8. Negative quantity: handled with EXCEPTION block
DO $$
BEGIN
    CALL dispense_medicine(1, '2024004', -5);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;
 
-- 9. Final results
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;
 