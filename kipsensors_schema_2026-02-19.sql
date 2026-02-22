-- KIPSensors Schema Export v2.3
-- Date: 2026-02-19 13:39:43.559125

SET FOREIGN_KEY_CHECKS = 0;

-- Table: Names
CREATE TABLE `Names` (
  `name_id` int NOT NULL AUTO_INCREMENT,
  `name_full` varchar(127) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`name_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1822 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table: Parts
CREATE TABLE `Parts` (
  `part_id` int NOT NULL AUTO_INCREMENT,
  `part_type` int NOT NULL,
  `quantity` int DEFAULT NULL,
  PRIMARY KEY (`part_id`),
  UNIQUE KEY `part_type` (`part_type`),
  CONSTRAINT `Parts_ibfk_1` FOREIGN KEY (`part_type`) REFERENCES `Types` (`type_id`)
) ENGINE=InnoDB AUTO_INCREMENT=124 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table: Places
CREATE TABLE `Places` (
  `place_id` int NOT NULL AUTO_INCREMENT,
  `place_row` varchar(7) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `place_axis` varchar(7) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `place_mark` varchar(7) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`place_id`)
) ENGINE=InnoDB AUTO_INCREMENT=67 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table: Roles
CREATE TABLE `Roles` (
  `role_id` int NOT NULL AUTO_INCREMENT,
  `role_name` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `role_description` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`role_id`),
  UNIQUE KEY `role_name` (`role_name`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table: Sensors
CREATE TABLE `Sensors` (
  `item_id` char(12) COLLATE utf8mb4_unicode_ci NOT NULL,
  `sensor_name` int NOT NULL,
  `sensor_type` int NOT NULL,
  `sensor_place` int NOT NULL,
  `sensor_status` int NOT NULL DEFAULT '1',
  `sensor_units` int NOT NULL,
  `sensor_lower` float NOT NULL,
  `sensor_upper` float NOT NULL,
  `sensor_protect` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`item_id`),
  KEY `sensor_name` (`sensor_name`),
  KEY `sensor_type` (`sensor_type`),
  KEY `sensor_place` (`sensor_place`),
  KEY `sensor_status` (`sensor_status`),
  KEY `sensor_units` (`sensor_units`),
  CONSTRAINT `Sensors_ibfk_1` FOREIGN KEY (`sensor_name`) REFERENCES `Names` (`name_id`),
  CONSTRAINT `Sensors_ibfk_2` FOREIGN KEY (`sensor_type`) REFERENCES `Types` (`type_id`),
  CONSTRAINT `Sensors_ibfk_3` FOREIGN KEY (`sensor_place`) REFERENCES `Places` (`place_id`),
  CONSTRAINT `Sensors_ibfk_4` FOREIGN KEY (`sensor_status`) REFERENCES `Statuses` (`status_id`),
  CONSTRAINT `Sensors_ibfk_5` FOREIGN KEY (`sensor_units`) REFERENCES `Units` (`unit_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table: StatusLog
CREATE TABLE `StatusLog` (
  `log_id` int NOT NULL AUTO_INCREMENT,
  `item_id` char(12) COLLATE utf8mb4_unicode_ci NOT NULL,
  `old_status` int DEFAULT NULL,
  `new_status` int DEFAULT NULL,
  `old_type` int DEFAULT NULL,
  `new_type` int DEFAULT NULL,
  `old_protect` tinyint(1) DEFAULT NULL,
  `new_protect` tinyint(1) DEFAULT NULL,
  `changed_by` int NOT NULL,
  `change_time` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`log_id`),
  KEY `item_id` (`item_id`),
  KEY `changed_by` (`changed_by`),
  CONSTRAINT `StatusLog_ibfk_1` FOREIGN KEY (`item_id`) REFERENCES `Sensors` (`item_id`),
  CONSTRAINT `StatusLog_ibfk_2` FOREIGN KEY (`changed_by`) REFERENCES `Users` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=34 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table: Statuses
CREATE TABLE `Statuses` (
  `status_id` int NOT NULL,
  `status_full` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`status_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table: Types
CREATE TABLE `Types` (
  `type_id` int NOT NULL AUTO_INCREMENT,
  `manufacturer` varchar(63) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `model` varchar(63) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`type_id`)
) ENGINE=InnoDB AUTO_INCREMENT=505 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table: Units
CREATE TABLE `Units` (
  `unit_id` int NOT NULL AUTO_INCREMENT,
  `unit_name` varchar(15) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`unit_id`)
) ENGINE=InnoDB AUTO_INCREMENT=26 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table: Users
CREATE TABLE `Users` (
  `user_id` int NOT NULL AUTO_INCREMENT,
  `username` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `password_hash` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `full_name` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `user_role` int NOT NULL,
  `is_active` tinyint(1) DEFAULT '1',
  PRIMARY KEY (`user_id`),
  UNIQUE KEY `username` (`username`),
  KEY `user_role` (`user_role`),
  CONSTRAINT `Users_ibfk_1` FOREIGN KEY (`user_role`) REFERENCES `Roles` (`role_id`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER //
DROP PROCEDURE IF EXISTS `AddNewSensor` //
CREATE PROCEDURE `AddNewSensor`(
    IN p_kks CHAR(12),
    IN p_name_text VARCHAR(255),
    IN p_type_id INT,
    IN p_row VARCHAR(10),
    IN p_axis VARCHAR(10),
    IN p_mark VARCHAR(10),
    IN p_unit_text VARCHAR(20), 
    IN p_lower FLOAT,
    IN p_upper FLOAT,
    IN p_is_protect TINYINT,
    OUT p_result INT 
)
BEGIN
    DECLARE v_name_id INT;
    DECLARE v_place_id INT;
    DECLARE v_unit_id INT;

    
    IF EXISTS (SELECT 1 FROM Sensors WHERE item_id = p_kks) THEN
        SET p_result = 0;
    ELSE
        
        SELECT name_id INTO v_name_id FROM Names WHERE name_full = p_name_text LIMIT 1;
        IF v_name_id IS NULL THEN
            INSERT INTO Names (name_full) VALUES (p_name_text);
            SET v_name_id = LAST_INSERT_ID();
        END IF;

        
        
        SELECT unit_id INTO v_unit_id FROM Units WHERE TRIM(unit_name) = TRIM(p_unit_text) LIMIT 1;
        IF v_unit_id IS NULL THEN
            INSERT INTO Units (unit_name) VALUES (p_unit_text);
            SET v_unit_id = LAST_INSERT_ID();
        END IF;

        
        SELECT place_id INTO v_place_id FROM Places 
        WHERE place_row = p_row AND place_axis = p_axis AND place_mark = p_mark LIMIT 1;
        IF v_place_id IS NULL THEN
            INSERT INTO Places (place_row, place_axis, place_mark) 
            VALUES (p_row, p_axis, p_mark);
            SET v_place_id = LAST_INSERT_ID();
        END IF;

        
        
        INSERT INTO Sensors (
            item_id, sensor_name, sensor_type, sensor_place, 
            sensor_status, sensor_protect, 
            sensor_units, 
            sensor_lower, sensor_upper
        )
        VALUES (
            p_kks, v_name_id, p_type_id, v_place_id, 
            1, p_is_protect, 
            v_unit_id, 
            p_lower, p_upper
        );

        SET p_result = v_place_id;
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `AddNewType` //
CREATE PROCEDURE `AddNewType`(
    IN p_manufacturer VARCHAR(50),
    IN p_model VARCHAR(50),
    OUT p_result INT 
)
BEGIN
    
    IF EXISTS (SELECT 1 FROM Types WHERE manufacturer = p_manufacturer AND model = p_model) THEN
        SET p_result = 0;
    ELSE
        INSERT INTO Types (manufacturer, model) 
        VALUES (p_manufacturer, p_model);
        
        SET p_result = LAST_INSERT_ID();
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `AddUser` //
CREATE PROCEDURE `AddUser`(
    IN p_username VARCHAR(50),
    IN p_full_name VARCHAR(100),
    IN p_group_name VARCHAR(20)
)
BEGIN
    DECLARE v_role_id INT;
    
    DECLARE v_default_hash VARCHAR(255) DEFAULT 'scrypt:32768:8:1$5EgZp9xJlBitqvCR$c629a5984bd334986504014ac8b1bb8e543f045d9d1195bf87a50beace53210faec617982ecdeeba4638a8089562afe191bf2cd34c1cffaf4badee8fbe6fb399';

    
    SELECT role_id INTO v_role_id FROM Roles WHERE role_name = p_group_name;

    IF v_role_id IS NOT NULL THEN
        INSERT INTO Users (username, full_name, password_hash, user_role, is_active)
        VALUES (p_username, p_full_name, v_default_hash, v_role_id, 1);
        
        SELECT CONCAT('Пользователь ', p_username, ' успешно добавлен.') AS Result;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ошибка: Группа (роль) не найдена в таблице Roles.';
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `DeactivateUser` //
CREATE PROCEDURE `DeactivateUser`(IN p_username VARCHAR(50))
BEGIN
    
    IF EXISTS (SELECT 1 FROM Users WHERE username = p_username) THEN
        UPDATE Users 
        SET is_active = 0, 
            password_hash = '' 
        WHERE username = p_username;
        
        SELECT CONCAT('Пользователь ', p_username, ' деактивирован. Доступ закрыт.') AS Result;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ошибка: Пользователь не найден.';
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `FullReport` //
CREATE PROCEDURE `FullReport`()
BEGIN
    SELECT 
        s.item_id AS KKS,
        n.name_full AS 'Диспетчерское наименование',
        CONCAT(t.manufacturer, ' ', t.model) AS 'Модель датчика',
        CONCAT('Ряд: ', p.place_row, ', Ось: ', p.place_axis, ', Отм.: ', p.place_mark) AS 'Местонахождение',
        st.status_full AS 'Текущее состояние',
        CASE 
            WHEN s.sensor_protect = 1 THEN 'Да' 
            ELSE 'Нет' 
        END AS 'Защитный'
    FROM 
        Sensors s
    JOIN Names n ON s.sensor_name = n.name_id
    JOIN Types t ON s.sensor_type = t.type_id
    JOIN Places p ON s.sensor_place = p.place_id
    JOIN Statuses st ON s.sensor_status = st.status_id;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `GetAllStatuses` //
CREATE PROCEDURE `GetAllStatuses`()
BEGIN
    SELECT status_id, status_full FROM Statuses ORDER BY status_id;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `GetAllTypes` //
CREATE PROCEDURE `GetAllTypes`()
BEGIN
    SELECT 
        type_id, 
        CONCAT(manufacturer, ' ', model) AS type_name 
    FROM Types 
    ORDER BY manufacturer, model;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `GetAllUnits` //
CREATE PROCEDURE `GetAllUnits`()
BEGIN
    SELECT unit_name FROM Units ORDER BY unit_name;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `GetAllUsers` //
CREATE PROCEDURE `GetAllUsers`()
BEGIN
    SELECT 
        u.user_id, 
        u.username, 
        u.full_name, 
        r.role_name, 
        u.is_active
    FROM Users u
    JOIN Roles r ON u.user_role = r.role_id
    ORDER BY u.is_active DESC, u.username ASC;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `GetSensorDetails` //
CREATE PROCEDURE `GetSensorDetails`(IN p_kks CHAR(12))
BEGIN
    SELECT 
        s.item_id AS KKS,                 
        n.name_full AS Name,               
        t.manufacturer AS Manufacturer,    
        t.model AS Model,                  
        p.place_row AS `Row`,               
        p.place_axis AS `Axis`,             
        p.place_mark AS `Mark`,             
        st.status_full AS Status,          
        u.unit_name AS Units,              
        s.sensor_lower AS Lower_Limit,     
        s.sensor_upper AS Upper_Limit,     
        s.sensor_protect AS Is_Protective, 
        COALESCE(pa.quantity, 0) AS Stock, 
        s.sensor_status AS Status_ID,      
        s.sensor_type AS Type_ID           
    FROM Sensors s
    JOIN Names n ON s.sensor_name = n.name_id
    JOIN Types t ON s.sensor_type = t.type_id
    JOIN Places p ON s.sensor_place = p.place_id
    JOIN Statuses st ON s.sensor_status = st.status_id
    JOIN Units u ON s.sensor_units = u.unit_id
    LEFT JOIN Parts pa ON pa.part_type = s.sensor_type
    WHERE s.item_id = p_kks;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `GetSensorHistory` //
CREATE PROCEDURE `GetSensorHistory`(IN p_kks CHAR(12))
BEGIN
    SELECT 
        sl.change_time AS 'Дата',
        u.full_name AS 'Кто изменил',
        s_old.status_full AS 'Был статус',
        s_new.status_full AS 'Стал статус',
        CASE WHEN sl.new_protect = 1 THEN 'Да' ELSE 'Нет' END AS 'Защита'
    FROM StatusLog sl
    JOIN Users u ON sl.changed_by = u.user_id
    LEFT JOIN Statuses s_old ON sl.old_status = s_old.status_id
    JOIN Statuses s_new ON sl.new_status = s_new.status_id
    WHERE sl.item_id = p_kks
    ORDER BY sl.change_time DESC;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `GetUserByID` //
CREATE PROCEDURE `GetUserByID`(IN p_id INT)
BEGIN
    SELECT u.user_id, u.username, u.full_name, r.role_name, r.role_description 
    FROM Users u 
    JOIN Roles r ON u.user_role = r.role_id 
    WHERE u.user_id = p_id AND u.is_active = 1;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `GetUserForAuth` //
CREATE PROCEDURE `GetUserForAuth`(IN p_username VARCHAR(50))
BEGIN
    SELECT u.user_id, u.username, u.password_hash, u.full_name, r.role_name, r.role_description, u.is_active 
    FROM Users u 
    JOIN Roles r ON u.user_role = r.role_id 
    WHERE u.username = p_username;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `ResetUserPassword` //
CREATE PROCEDURE `ResetUserPassword`(IN p_username VARCHAR(50))
BEGIN
    DECLARE v_default_hash VARCHAR(255) DEFAULT 'scrypt:32768:8:1$5EgZp9xJlBitqvCR$c629a5984bd334986504014ac8b1bb8e543f045d9d1195bf87a50beace53210faec617982ecdeeba4638a8089562afe191bf2cd34c1cffaf4badee8fbe6fb399';

    IF EXISTS (SELECT 1 FROM Users WHERE username = p_username) THEN
        UPDATE Users 
        SET password_hash = v_default_hash,
            is_active = 1
        WHERE username = p_username;
        
        SELECT CONCAT('Пароль пользователя ', p_username, ' сброшен на стандартный (123456).') AS Result;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ошибка: Пользователь не найден.';
    END IF;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `SearchByKKS` //
CREATE PROCEDURE `SearchByKKS`(IN p_pattern VARCHAR(50))
BEGIN
    
    SET @p = REPLACE(p_pattern, '*', '%');
    
    SELECT 
        s.item_id AS KKS,
        n.name_full AS 'Диспетчерское наименование',
        st.status_full AS 'Текущее состояние',
        CASE WHEN s.sensor_protect = 1 THEN 'Да' ELSE 'Нет' END AS 'Защитный'
    FROM Sensors s
    JOIN Names n ON s.sensor_name = n.name_id
    JOIN Statuses st ON s.sensor_status = st.status_id
    WHERE s.item_id LIKE @p;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `SearchByName` //
CREATE PROCEDURE `SearchByName`(IN p_pattern VARCHAR(100))
BEGIN
    SET @p = REPLACE(p_pattern, '*', '%');
    
    SELECT 
        s.item_id AS KKS,
        n.name_full AS 'Диспетчерское наименование',
        st.status_full AS 'Текущее состояние',
        CASE WHEN s.sensor_protect = 1 THEN 'Да' ELSE 'Нет' END AS 'Защитный'
    FROM Sensors s
    JOIN Names n ON s.sensor_name = n.name_id
    JOIN Statuses st ON s.sensor_status = st.status_id
    WHERE n.name_full LIKE @p;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `SmallReport` //
CREATE PROCEDURE `SmallReport`()
BEGIN
    SELECT 
        s.item_id AS KKS,
        n.name_full AS 'Диспетчерское наименование',
        st.status_full AS 'Текущее состояние',
        CASE 
            WHEN s.sensor_protect = 1 THEN 'Да' 
            ELSE 'Нет' 
        END AS 'Защитный'
    FROM 
        Sensors s
    JOIN Names n ON s.sensor_name = n.name_id
    JOIN Statuses st ON s.sensor_status = st.status_id
    WHERE 
        s.sensor_status != 1;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `sp_delete_sensor` //
CREATE PROCEDURE `sp_delete_sensor`(IN p_item_id CHAR(12))
BEGIN
    
    DECLARE v_name_id INT;
    DECLARE v_place_id INT;
    DECLARE v_unit_id INT;
    
    
    SELECT sensor_name, sensor_place, sensor_units 
    INTO v_name_id, v_place_id, v_unit_id
    FROM Sensors 
    WHERE item_id = p_item_id;

    
    IF v_name_id IS NOT NULL THEN
        
        
        DELETE FROM StatusLog WHERE item_id = p_item_id;

        
        DELETE FROM Sensors WHERE item_id = p_item_id;

        
        
        IF NOT EXISTS (SELECT 1 FROM Sensors WHERE sensor_name = v_name_id) THEN
            DELETE FROM Names WHERE name_id = v_name_id;
        END IF;

        
        
        IF NOT EXISTS (SELECT 1 FROM Sensors WHERE sensor_place = v_place_id) THEN
            DELETE FROM Places WHERE place_id = v_place_id;
        END IF;

        
        
        IF NOT EXISTS (SELECT 1 FROM Sensors WHERE sensor_units = v_unit_id) THEN
            DELETE FROM Units WHERE unit_id = v_unit_id;
        END IF;

    END IF;
END //
DELIMITER ;

DELIMITER //
DROP PROCEDURE IF EXISTS `UpdateSensorData` //
CREATE PROCEDURE `UpdateSensorData`(
    IN p_kks CHAR(12),
    IN p_user_id INT,
    IN p_new_status INT,
    IN p_new_type INT,
    IN p_new_protect BOOL,
    IN p_new_stock INT        
)
BEGIN
    
    
    IF EXISTS (
        SELECT 1 FROM Sensors 
        WHERE item_id = p_kks 
          AND (sensor_status != p_new_status 
               OR sensor_type != p_new_type 
               OR sensor_protect != p_new_protect)
    ) THEN
        
        INSERT INTO StatusLog (
            item_id, old_status, new_status, 
            old_type, new_type, 
            old_protect, new_protect, 
            changed_by
        )
        SELECT 
            item_id, sensor_status, p_new_status, 
            sensor_type, p_new_type, 
            sensor_protect, p_new_protect, 
            p_user_id
        FROM Sensors WHERE item_id = p_kks;

        
        UPDATE Sensors SET 
            sensor_status = p_new_status,
            sensor_type = p_new_type,
            sensor_protect = p_new_protect
        WHERE item_id = p_kks;
    END IF;

    
    
    INSERT INTO Parts (part_type, quantity) 
    VALUES (p_new_type, p_new_stock)
    ON DUPLICATE KEY UPDATE quantity = p_new_stock;
    
    
    SELECT 'OK' AS Result;
END //
DELIMITER ;

SET FOREIGN_KEY_CHECKS = 1;
