-- Bảng lưu lịch sử chuyến xe Grab
CREATE TABLE IF NOT EXISTS `phone_grab_history` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `ride_id` varchar(100) NOT NULL,
  `driver_citizenid` varchar(50) DEFAULT NULL,
  `passenger_citizenid` varchar(50) DEFAULT NULL,
  `pickup_coords` text DEFAULT NULL,
  `dropoff_coords` text DEFAULT NULL,
  `distance` int(11) DEFAULT 0,
  `price` int(11) DEFAULT 0,
  `status` varchar(20) DEFAULT 'completed',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `driver_citizenid` (`driver_citizenid`),
  KEY `passenger_citizenid` (`passenger_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Bảng thống kê tài xế Grab
CREATE TABLE IF NOT EXISTS `phone_grab_drivers` (
  `citizenid` varchar(50) NOT NULL,
  `total_rides` int(11) DEFAULT 0,
  `total_earnings` int(11) DEFAULT 0,
  `rating` decimal(3,2) DEFAULT 5.00,
  `is_active` tinyint(1) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
