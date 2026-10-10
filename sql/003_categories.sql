CREATE TABLE IF NOT EXISTS `qbdoorlock_categories` (
    `id` VARCHAR(48) NOT NULL,
    `label` VARCHAR(96) NOT NULL,
    `defaults` LONGTEXT NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
