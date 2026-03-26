SELECT MAX(scheduled_departure)
FROM flights;

SELECT status, COUNT(1)
FROM flights
GROUP BY status;

-- https://www.cybertec-postgresql.com/en/update-limit-in-postgresql/
WITH one_scheduled_flight AS MATERIALIZED (
   SELECT flight_id FROM flights f
   WHERE f.status = 'Scheduled'
   AND f.scheduled_arrival > f.scheduled_departure + INTERVAL '1 MINUTE'
   FOR NO KEY UPDATE SKIP LOCKED
   LIMIT 1
)
UPDATE flights AS f
SET scheduled_departure = scheduled_departure + INTERVAL '1 MINUTE'
FROM one_scheduled_flight WHERE f.flight_id = one_scheduled_flight.flight_id
RETURNING *;

