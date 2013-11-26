--
-- category of temporary password is not mandatory
--

ALTER TABLE `temporary_password` MODIFY category int DEFAULT NULL;

---
--- Add a column to store the time balance of a node
---
ALTER TABLE node ADD `time_balance` int unsigned AFTER `lastskip`;

---
--- Add a column to store the bandwidth balance of a node
---
ALTER TABLE node ADD `bandwidth_balance` int unsigned AFTER `time_balance`;
