-- Grab App Database Tables
-- Run this SQL to create the necessary tables for the Grab app

-- Table to store ride history
CREATE TABLE IF NOT EXISTS `grab_rides` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `ride_id` varchar(50) NOT NULL,
    `passenger_id` varchar(50) NOT NULL,
    `driver_id` varchar(50) NOT NULL,
    `pickup_coords` text NOT NULL,
    `dropoff_coords` text DEFAULT NULL,
    `distance` int(11) NOT NULL DEFAULT 0,
    `price` int(11) NOT NULL DEFAULT 0,
    `status` enum('waiting','accepted','pickedup','completed','cancelled') NOT NULL DEFAULT 'waiting',
    `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
    `completed_at` timestamp NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `ride_id` (`ride_id`),
    KEY `passenger_id` (`passenger_id`),
    KEY `driver_id` (`driver_id`),
    KEY `status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table to store driver statistics
CREATE TABLE IF NOT EXISTS `grab_driver_stats` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `driver_id` varchar(50) NOT NULL,
    `total_rides` int(11) NOT NULL DEFAULT 0,
    `total_earnings` int(11) NOT NULL DEFAULT 0,
    `rating` decimal(3,2) NOT NULL DEFAULT 5.00,
    `total_ratings` int(11) NOT NULL DEFAULT 0,
    `is_active` tinyint(1) NOT NULL DEFAULT 0,
    `last_active` timestamp NULL DEFAULT NULL,
    `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
    `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
    PRIMARY KEY (`id`),
    UNIQUE KEY `driver_id` (`driver_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table to store passenger statistics
CREATE TABLE IF NOT EXISTS `grab_passenger_stats` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `passenger_id` varchar(50) NOT NULL,
    `total_rides` int(11) NOT NULL DEFAULT 0,
    `total_spent` int(11) NOT NULL DEFAULT 0,
    `rating` decimal(3,2) NOT NULL DEFAULT 5.00,
    `total_ratings` int(11) NOT NULL DEFAULT 0,
    `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
    `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
    PRIMARY KEY (`id`),
    UNIQUE KEY `passenger_id` (`passenger_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table to store ride ratings
CREATE TABLE IF NOT EXISTS `grab_ratings` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `ride_id` varchar(50) NOT NULL,
    `rater_id` varchar(50) NOT NULL,
    `rated_id` varchar(50) NOT NULL,
    `rating` int(1) NOT NULL CHECK (`rating` >= 1 AND `rating` <= 5),
    `comment` text DEFAULT NULL,
    `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_rating` (`ride_id`, `rater_id`),
    KEY `rated_id` (`rated_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;