DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS lab_sessions;
 
-- 1. Tables and sample data
CREATE TABLE lab_sessions (
    session_id             SERIAL PRIMARY KEY,
    session_name           VARCHAR(60) NOT NULL,
    available_workstations INT NOT NULL CHECK (available_workstations >= 0)
);
 
CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,
    session_id     INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer       VARCHAR(60) NOT NULL,
    workstations   INT NOT NULL CHECK (workstations > 0),
    status         VARCHAR(10) NOT NULL DEFAULT 'RESERVED'
                   CHECK (status IN ('RESERVED','CANCELLED'))
);
 
INSERT INTO lab_sessions (session_name, available_workstations) VALUES
 ('Monday 08:00 - Programming Lab', 30),
 ('Tuesday 10:00 - Database Lab', 5),
 ('Wednesday 14:00 - Networking Lab', 0);
 
-- 2. IF / ELSIF / ELSE
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT session_name, available_workstations FROM lab_sessions ORDER BY session_id LOOP
        IF r.available_workstations = 0 THEN
            RAISE NOTICE '%: FULL', r.session_name;
        ELSIF r.available_workstations <= 5 THEN
            RAISE NOTICE '%: NEARLY FULL (% left)', r.session_name, r.available_workstations;
        ELSE
            RAISE NOTICE '%: enough workstations (%)', r.session_name, r.available_workstations;
        END IF;
    END LOOP;
END $$;
 
-- 3. WHILE and numeric FOR
DO $$
DECLARE
    n INT := 1;
BEGIN
    WHILE n <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', n;
        n := n + 1;
    END LOOP;
 
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Workstation check %', i;
    END LOOP;
END $$;
 
-- 4. reserve_workstations procedure
CREATE OR REPLACE PROCEDURE reserve_workstations(p_session_id INT, p_lecturer VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: % (must be greater than zero)', p_qty;
    END IF;
 
    SELECT available_workstations INTO v_available
    FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;
 
    IF NOT FOUND THEN
        RAISE NOTICE 'Session % does not exist.', p_session_id;
        RETURN;
    END IF;
 
    IF v_available < p_qty THEN
        RAISE NOTICE 'Reservation REJECTED for %: requested %, only % available.', p_lecturer, p_qty, v_available;
        RETURN;
    END IF;
 
    UPDATE lab_sessions SET available_workstations = available_workstations - p_qty
    WHERE session_id = p_session_id;
    INSERT INTO reservations (session_id, lecturer, workstations) VALUES (p_session_id, p_lecturer, p_qty);
    RAISE NOTICE 'Reservation recorded for %: % workstation(s).', p_lecturer, p_qty;
END $$;
 
-- 5. Two valid reservations and one exceeding capacity
CALL reserve_workstations(1, 'Dr. Banda', 20);   
CALL reserve_workstations(2, 'Mr. Phiri', 3);    
CALL reserve_workstations(2, 'Ms. Mumba', 10);   
 
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
 
-- 6. cancel_reservation procedure
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session INT;
    v_qty     INT;
    v_status  VARCHAR;
BEGIN
    SELECT session_id, workstations, status INTO v_session, v_qty, v_status
    FROM reservations WHERE reservation_id = p_reservation_id FOR UPDATE;
 
    IF NOT FOUND THEN
        RAISE NOTICE 'Reservation % not found.', p_reservation_id;
        RETURN;
    END IF;
 
    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % already cancelled. No workstations released.', p_reservation_id;
        RETURN;
    END IF;
 
    UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
    UPDATE lab_sessions SET available_workstations = available_workstations + v_qty
    WHERE session_id = v_session;
    RAISE NOTICE 'Reservation % cancelled. % workstation(s) released.', p_reservation_id, v_qty;
END $$;
 
CALL cancel_reservation(1);   
CALL cancel_reservation(1);   
 
SELECT * FROM lab_sessions ORDER BY session_id;
 
-- 7. Explicit cursor: sessions with few workstations remaining
DO $$
DECLARE
    cur_few CURSOR FOR
        SELECT session_name, available_workstations FROM lab_sessions
        WHERE available_workstations <= 5 ORDER BY available_workstations;
    v_name lab_sessions.session_name%TYPE;
    v_free lab_sessions.available_workstations%TYPE;
BEGIN
    OPEN cur_few;
    LOOP
        FETCH cur_few INTO v_name, v_free;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations remaining: % (% left)', v_name, v_free;
    END LOOP;
    CLOSE cur_few;
END $$;
 
-- 8. Zero workstations: handled with EXCEPTION block
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Zulu', 0);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;
 
-- 9. Final results
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
 