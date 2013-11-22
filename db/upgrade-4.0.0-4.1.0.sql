--
-- category of temporary password is not mandatory
--

ALTER TABLE `temporary_password` MODIFY category int DEFAULT NULL;

---
--- Add a column to store the remaining available bandwidth usage of a node
---
ALTER TABLE node ADD `bandwidth_balance` int unsigned AFTER `time_balance`;
