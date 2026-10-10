CREATE TABLE IF NOT EXISTS `qbdoorlock_links` (
    `door_id` VARCHAR(64) NOT NULL,
    `linked_door_id` VARCHAR(64) NOT NULL,
    PRIMARY KEY (`door_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
