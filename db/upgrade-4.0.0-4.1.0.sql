--
-- category of temporary password is not mandatory
--

ALTER TABLE `temporary_password` MODIFY category int DEFAULT NULL;

--
-- Alter for dynamic controller
--

ALTER TABLE locationlog 
    ADD `switch_ip` varchar(17) DEFAULT NULL,
    ADD `switch_mac` varchar(17) DEFAULT NULL;

UPDATE locationlog SET switch_ip = switch;
