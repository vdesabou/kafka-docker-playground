DROP TABLE IF EXISTS cities;
CREATE TABLE cities (city_id INTEGER KEY NOT NULL, name VARCHAR(255), state VARCHAR(255));
INSERT INTO cities (city_id, name, state) VALUES (1, 'Raleigh', 'NC');
INSERT INTO cities (city_id, name, state) VALUES (2, 'Mountain View', 'CA');
INSERT INTO cities (city_id, name, state) VALUES (3, 'Knoxville', 'TN');
INSERT INTO cities (city_id, name, state) VALUES (4, 'Houston', 'TX');
INSERT INTO cities (city_id, name, state) VALUES (5, 'Olympia', 'WA');
INSERT INTO cities (city_id, name, state) VALUES (6, 'Bismarck', 'ND');