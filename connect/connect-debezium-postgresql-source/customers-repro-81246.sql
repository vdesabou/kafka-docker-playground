create table CUSTOMERS (
        id INT PRIMARY KEY,
        first_name VARCHAR(50),
        last_name VARCHAR(50),
        email VARCHAR(50),
        gender VARCHAR(50),
        club_status VARCHAR(8),
        comments VARCHAR(90),
        create_ts timestamp DEFAULT CURRENT_TIMESTAMP,
        update_ts timestamp DEFAULT CURRENT_TIMESTAMP,
        curr_amount numeric(14,2) NOT NULL DEFAULT NULL::numeric
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

insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (1, 'Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (2, 'Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (3, 'Mariejeanne', 'Cocci', 'mcocci2@techcrunch.com', 'Female', 'bronze', 'Multi-tiered bandwidth-monitored capability', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (4, 'Hashim', 'Rumke', 'hrumke3@sohu.com', 'Male', 'platinum', 'Self-enabling 24/7 firmware', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (5, 'Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (6, 'Robinet', 'Leheude', 'rleheude5@reddit.com', 'Female', 'platinum', 'Virtual upward-trending definition', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (7, 'Fay', 'Huc', 'fhuc6@quantcast.com', 'Female', 'bronze', 'Operative composite capacity', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (8, 'Patti', 'Rosten', 'prosten7@ihg.com', 'Female', 'silver', 'Integrated bandwidth-monitored instruction set', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (9, 'Even', 'Tinham', 'etinham8@facebook.com', 'Male', 'silver', 'Virtual full-range info-mediaries', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (10, 'Brena', 'Tollerton', 'btollerton9@furl.net', 'Female', 'silver', 'Diverse tangible methodology', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (11, 'Alexandro', 'Peeke-Vout', 'apeekevouta@freewebs.com', 'Male', 'gold', 'Ameliorated value-added orchestration', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (12, 'Sheryl', 'Hackwell', 'shackwellb@paginegialle.it', 'Female', 'gold', 'Self-enabling global parallelism', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (13, 'Laney', 'Toopin', 'ltoopinc@icio.us', 'Female', 'platinum', 'Phased coherent alliance', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (14, 'Isabelita', 'Talboy', 'italboyd@imageshack.us', 'Female', 'gold', 'Cloned transitional synergy', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (15, 'Rodrique', 'Silverton', 'rsilvertone@umn.edu', 'Male', 'gold', 'Re-engineered static application', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (16, 'Clair', 'Vardy', 'cvardyf@reverbnation.com', 'Male', 'bronze', 'Expanded bottom-line Graphical User Interface', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (17, 'Brianna', 'Paradise', 'bparadiseg@nifty.com', 'Female', 'bronze', 'Open-source global toolset', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (18, 'Waldon', 'Keddey', 'wkeddeyh@weather.com', 'Male', 'gold', 'Business-focused multi-state functionalities', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (19, 'Josiah', 'Brockett', 'jbrocketti@com.com', 'Male', 'gold', 'Realigned didactic info-mediaries', 1.2);
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, curr_amount) values (20, 'Anselma', 'Rook', 'arookj@europa.eu', 'Female', 'gold', 'Cross-group 24/7 application', 1.2);
