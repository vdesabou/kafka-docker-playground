create table CUSTOMERS (
        id INT PRIMARY KEY,
        first_name VARCHAR(50),
        last_name VARCHAR(50),
        email VARCHAR(50),
        gender VARCHAR(50),
        club_status VARCHAR(8),
        comments VARCHAR(90),
        create_ts timestamp DEFAULT CURRENT_TIMESTAMP ,
        update_ts timestamp DEFAULT CURRENT_TIMESTAMP,
        tsm VARCHAR(50)
);


-- Courtesy of https://techblog.covermymeds.com/databases/on-update-timestamps-mysql-vs-postgres/
CREATE FUNCTION update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    NEW.update_ts = NOW();
    RETURN NEW;
  END;
$$;

CREATE TRIGGER t1_updated_at_modtime BEFORE UPDATE ON CUSTOMERS FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, tsm) values (1, 'Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy', '2022-04-25 12:05:54.035338+05:30');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, tsm) values (2, 'Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface', '2022-04-25 12:05:54.035338+05:30');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, tsm) values (3, 'Mariejeanne', 'Cocci', 'mcocci2@techcrunch.com', 'Female', 'bronze', 'Multi-tiered bandwidth-monitored capability', '2022-04-25 12:05:54.035338+05:30');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, tsm) values (4, 'Hashim', 'Rumke', 'hrumke3@sohu.com', 'Male', 'platinum', 'Self-enabling 24/7 firmware', '2022-04-25 12:05:54.035338+05:30');
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, tsm) values (5, 'Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach', '2022-04-25 12:05:54.035338+05:30');
