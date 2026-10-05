DROP TABLE IF EXISTS allocations;
DROP TABLE IF EXISTS hostel_rooms;
 
-- 1. Tables and sample data
CREATE TABLE hostel_rooms (
    room_id          SERIAL PRIMARY KEY,
    room_number      VARCHAR(10) NOT NULL UNIQUE,
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);
 
CREATE TABLE allocations (
    allocation_id  SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id        INT NOT NULL REFERENCES hostel_rooms(room_id),
    status         VARCHAR(12) NOT NULL DEFAULT 'ALLOCATED'
                   CHECK (status IN ('ALLOCATED','COMPLETE'))
);
 
INSERT INTO hostel_rooms (room_number, available_spaces) VALUES
 ('A101', 4),
 ('A102', 1),
 ('B201', 0);
 
-- 2. IF / ELSIF / ELSE
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT room_number, available_spaces FROM hostel_rooms ORDER BY room_id LOOP
        IF r.available_spaces = 0 THEN
            RAISE NOTICE 'Room %: FULL', r.room_number;
        ELSIF r.available_spaces = 1 THEN
            RAISE NOTICE 'Room %: one space left', r.room_number;
        ELSE
            RAISE NOTICE 'Room %: several spaces (%)', r.room_number, r.available_spaces;
        END IF;
    END LOOP;
END $$;
 
-- 3. WHILE and numeric FOR
DO $$
DECLARE
    d INT := 1;
BEGIN
    WHILE d <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', d;
        d := d + 1;
    END LOOP;
 
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Room check %', i;
    END LOOP;
END $$;
 
-- 4. allocate_room procedure
CREATE OR REPLACE PROCEDURE allocate_room(p_student VARCHAR, p_room_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_spaces INT;
BEGIN
    IF p_student IS NULL OR btrim(p_student) = '' THEN
        RAISE EXCEPTION 'Invalid student number: it cannot be blank';
    END IF;
 
    SELECT available_spaces INTO v_spaces
    FROM hostel_rooms WHERE room_id = p_room_id FOR UPDATE;
 
    IF NOT FOUND THEN
        RAISE NOTICE 'Room % does not exist.', p_room_id;
        RETURN;
    END IF;
 
    IF v_spaces < 1 THEN
        RAISE NOTICE 'Allocation REJECTED for %: room % is full.', p_student, p_room_id;
        RETURN;
    END IF;
 
    UPDATE hostel_rooms SET available_spaces = available_spaces - 1 WHERE room_id = p_room_id;
    INSERT INTO allocations (student_number, room_id) VALUES (p_student, p_room_id);
    RAISE NOTICE 'Student % allocated to room %.', p_student, p_room_id;
END $$;
 
-- 5. Two valid allocations and one to a full room
CALL allocate_room('2024001', 1);   
CALL allocate_room('2024002', 2);   
CALL allocate_room('2024003', 3);   
 
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
 
-- 6. check_out procedure
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room   INT;
    v_status VARCHAR;
BEGIN
    SELECT room_id, status INTO v_room, v_status
    FROM allocations WHERE allocation_id = p_allocation_id FOR UPDATE;
 
    IF NOT FOUND THEN
        RAISE NOTICE 'Allocation % not found.', p_allocation_id;
        RETURN;
    END IF;
 
    IF v_status = 'COMPLETE' THEN
        RAISE NOTICE 'Allocation % already complete. No space freed.', p_allocation_id;
        RETURN;
    END IF;
 
    UPDATE allocations SET status = 'COMPLETE' WHERE allocation_id = p_allocation_id;
    UPDATE hostel_rooms SET available_spaces = available_spaces + 1 WHERE room_id = v_room;
    RAISE NOTICE 'Allocation % checked out. One bed space released.', p_allocation_id;
END $$;
 
CALL check_out(1);  
CALL check_out(1);   
 
SELECT * FROM hostel_rooms ORDER BY room_id;
 
-- 7. Explicit cursor: full or nearly full rooms
DO $$
DECLARE
    cur_rooms CURSOR FOR
        SELECT room_number, available_spaces FROM hostel_rooms
        WHERE available_spaces <= 1 ORDER BY available_spaces;
    v_room   hostel_rooms.room_number%TYPE;
    v_spaces hostel_rooms.available_spaces%TYPE;
BEGIN
    OPEN cur_rooms;
    LOOP
        FETCH cur_rooms INTO v_room, v_spaces;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Full or nearly full: room % (% space(s) left)', v_room, v_spaces;
    END LOOP;
    CLOSE cur_rooms;
END $$;
 
-- 8. Blank student number: handled with EXCEPTION block
DO $$
BEGIN
    CALL allocate_room('   ', 1);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;
 
-- 9. Final results
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
 