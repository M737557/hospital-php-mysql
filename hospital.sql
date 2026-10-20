-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Gegenereerd op: 20 okt 2026 om 15:45
-- Serverversie: 10.4.32-MariaDB
-- PHP-versie: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `hospital`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_detach_discharged` (IN `p_cutoff` DATETIME, IN `p_source` VARCHAR(20), OUT `p_moved` INT)   BEGIN
    DECLARE v_moved INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_detach;
        RESIGNAL;
    END;
    SET p_moved = 0;

    DROP TEMPORARY TABLE IF EXISTS tmp_detach;
    CREATE TEMPORARY TABLE tmp_detach (id VARCHAR(20) PRIMARY KEY) ENGINE=MEMORY;

    START TRANSACTION;

    -- lock the rows that will move
    INSERT INTO tmp_detach (id)
        SELECT id FROM patients
         WHERE status = 'discharged'
           AND discharge_date IS NOT NULL
           AND discharge_date < p_cutoff
         FOR UPDATE;

    INSERT INTO detached_patients
        (id, discharge_date, status, department, room_id, room_num, gender, admit_date,
         archive_week, detached_at, detached_from, photos_deleted, data_rot47)
    SELECT p.id, p.discharge_date, p.status, p.department, p.room_id, p.room_num, p.gender, p.admit_date,
           DATE_FORMAT(p.discharge_date, '%v-%x'), NOW(),
           IF(p_source = 'manual', 'manual_detachment', 'weekly_detachment'), 0, p.data_rot47
      FROM patients p
      JOIN tmp_detach t ON t.id = p.id
    ON DUPLICATE KEY UPDATE data_rot47 = VALUES(data_rot47);

    DELETE p FROM patients p JOIN tmp_detach t ON t.id = p.id;
    SET v_moved = ROW_COUNT();

    INSERT INTO detach_runs (run_at, cutoff, moved, source) VALUES (NOW(), p_cutoff, v_moved, p_source);
    INSERT INTO app_kv (k, v) VALUES ('last_detach_boundary', DATE_FORMAT(p_cutoff, '%Y-%m-%d %H:%i:%s'))
        ON DUPLICATE KEY UPDATE v = GREATEST(v, VALUES(v));

    COMMIT;
    DROP TEMPORARY TABLE IF EXISTS tmp_detach;
    SET p_moved = v_moved;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_snapshot_occupancy` (IN `p_date` DATE)   BEGIN
    INSERT INTO occupancy_snapshots (snapshot_date, room_id, dept, beds, occ, patients)
    SELECT p_date, r.id, r.dept, r.beds, r.occ,
           (SELECT COUNT(*) FROM patients p WHERE p.room_id = r.id AND p.status = 'admitted')
      FROM rooms r
    ON DUPLICATE KEY UPDATE beds = VALUES(beds), occ = VALUES(occ), patients = VALUES(patients);
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Tabelstructuur voor tabel `activity_log`
--

CREATE TABLE `activity_log` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `logged_at` datetime NOT NULL,
  `username` varchar(60) NOT NULL DEFAULT 'guest',
  `ip` varchar(45) NOT NULL DEFAULT '',
  `type` varchar(20) NOT NULL DEFAULT 'other',
  `patient_id` varchar(20) DEFAULT NULL,
  `message` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tabelstructuur voor tabel `app_kv`
--

CREATE TABLE `app_kv` (
  `k` varchar(60) NOT NULL,
  `v` longtext DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Gegevens worden geëxporteerd voor tabel `app_kv`
--

INSERT INTO `app_kv` (`k`, `v`, `updated_at`) VALUES
('activity_log_purged', '2026-10-20', '2026-10-20 13:11:11'),
('medications_seeded', '2026-10-20 15:34:21', '2026-10-20 13:34:21');

-- --------------------------------------------------------

--
-- Tabelstructuur voor tabel `detached_patients`
--

CREATE TABLE `detached_patients` (
  `id` varchar(20) NOT NULL,
  `discharge_date` datetime NOT NULL,
  `status` varchar(20) NOT NULL DEFAULT 'discharged',
  `department` varchar(40) NOT NULL DEFAULT '',
  `room_id` int(11) DEFAULT NULL,
  `room_num` varchar(20) DEFAULT NULL,
  `gender` varchar(30) DEFAULT NULL,
  `admit_date` datetime DEFAULT NULL,
  `archive_week` char(7) NOT NULL,
  `detached_at` datetime NOT NULL,
  `detached_from` varchar(40) NOT NULL DEFAULT 'weekly_detachment',
  `photos_deleted` tinyint(1) NOT NULL DEFAULT 0,
  `data_rot47` longtext NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tabelstructuur voor tabel `detach_runs`
--

CREATE TABLE `detach_runs` (
  `run_id` int(11) NOT NULL,
  `run_at` datetime NOT NULL,
  `cutoff` datetime NOT NULL,
  `moved` int(11) NOT NULL,
  `source` varchar(20) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tabelstructuur voor tabel `medications`
--

CREATE TABLE `medications` (
  `id` varchar(20) NOT NULL,
  `category` varchar(60) NOT NULL DEFAULT 'Other',
  `name` varchar(120) NOT NULL,
  `strength` varchar(60) DEFAULT NULL,
  `dose` varchar(80) DEFAULT NULL,
  `frequency` varchar(80) DEFAULT NULL,
  `duration` varchar(60) DEFAULT NULL,
  `instructions` varchar(300) DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Gegevens worden geëxporteerd voor tabel `medications`
--

INSERT INTO `medications` (`id`, `category`, `name`, `strength`, `dose`, `frequency`, `duration`, `instructions`, `active`) VALUES
('M008919db', 'Other', 'Vitamin D3', '800 IU tablet', '', '', '', '', 1),
('M0735b577', 'Neurology and psychiatry', 'Sertraline', '50 mg tablet', '', '', '', '', 1),
('M08a36f42', 'Pain and fever', 'Tramadol', '50 mg capsule', '', '', '', '', 1),
('M19244144', 'Diabetes and endocrine', 'Gliclazide', '30 mg modified-release tablet', '', '', '', '', 1),
('M1bcba42d', 'Diabetes and endocrine', 'Insulin (as prescribed)', '100 IU/ml', '', '', '', '', 1),
('M21384a25', 'Respiratory and allergy', 'Salbutamol, inhaler', '100 mcg/dose', '', '', '', '', 1),
('M25f19023', 'Gastrointestinal', 'Macrogol', 'sachet', '', '', '', '', 1),
('M267a72dc', 'Antibiotics', 'Azithromycin', '250 mg tablet', '', '', '', '', 1),
('M37385cda', 'Antibiotics', 'Doxycycline', '100 mg capsule', '', '', '', '', 1),
('M3771fb6a', 'Neurology and psychiatry', 'Levetiracetam', '500 mg tablet', '', '', '', '', 1),
('M3f99c9f7', 'Antibiotics', 'Ciprofloxacin', '250 mg tablet', '', '', '', '', 1),
('M40d96c5a', 'Neurology and psychiatry', 'Lorazepam', '1 mg tablet', '', '', '', '', 1),
('M4598950b', 'Pain and fever', 'Naproxen', '250 mg tablet', '', '', '', '', 1),
('M4d182fa1', 'Antibiotics', 'Flucloxacillin', '500 mg capsule', '', '', '', '', 1),
('M500665a9', 'Other', 'Iron (ferrous fumarate)', '200 mg tablet', '', '', '', '', 1),
('M5341820d', 'Respiratory and allergy', 'Loratadine', '10 mg tablet', '', '', '', '', 1),
('M588661da', 'Cardiovascular', 'Clopidogrel', '75 mg tablet', '', '', '', '', 1),
('M64f57b81', 'Gastrointestinal', 'Lactulose', '667 mg/ml syrup', '', '', '', '', 1),
('M650ceb11', 'Respiratory and allergy', 'Budesonide, inhaler', '200 mcg/dose', '', '', '', '', 1),
('M688cabe6', 'Antibiotics', 'Amoxicillin', '250 mg capsule', '', '', '', '', 1),
('M6c9f9359', 'Cardiovascular', 'Metoprolol', '50 mg tablet', '', '', '', '', 1),
('M6fa63feb', 'Neurology and psychiatry', 'Diazepam', '2 mg tablet', '', '', '', '', 1),
('M7a06b512', 'Cardiovascular', 'Apixaban', '2.5 mg tablet', '', '', '', '', 1),
('M80c3363e', 'Diabetes and endocrine', 'Levothyroxine', '25 mcg tablet', '', '', '', '', 1),
('M82a7afc0', 'Gastrointestinal', 'Ondansetron', '4 mg tablet', '', '', '', '', 1),
('M85dd6c1e', 'Antibiotics', 'Amoxicillin/clavulanic acid', '500/125 mg tablet', '', '', '', '', 1),
('M8998b68e', 'Gastrointestinal', 'Pantoprazole', '20 mg tablet', '', '', '', '', 1),
('M8d0ccf60', 'Cardiovascular', 'Simvastatin', '20 mg tablet', '', '', '', '', 1),
('M9167bd19', 'Respiratory and allergy', 'Prednisolone', '5 mg tablet', '', '', '', '', 1),
('M99598619', 'Cardiovascular', 'Amlodipine', '5 mg tablet', '', '', '', '', 1),
('M9c4d9b4f', 'Cardiovascular', 'Nitroglycerin (GTN), spray', '0.4 mg/dose, spray', '', '', '', '', 1),
('Ma05b0e03', 'Other', 'Potassium chloride', '600 mg prolonged-release tablet', '', '', '', '', 1),
('Mae9e1aa8', 'Gastrointestinal', 'Omeprazole', '20 mg capsule', '', '', '', '', 1),
('Mbb18e5f0', 'Respiratory and allergy', 'Cetirizine', '10 mg tablet', '', '', '', '', 1),
('Mbc9b2d63', 'Cardiovascular', 'Bisoprolol', '2.5 mg tablet', '', '', '', '', 1),
('Mbdb1fc6d', 'Other', 'Folic acid', '0.4 mg tablet', '', '', '', '', 1),
('Mbdd43829', 'Cardiovascular', 'Lisinopril', '5 mg tablet', '', '', '', '', 1),
('Mc1d2b1c0', 'Cardiovascular', 'Furosemide', '20 mg tablet', '', '', '', '', 1),
('Mc504c40f', 'Gastrointestinal', 'Metoclopramide', '10 mg tablet', '', '', '', '', 1),
('Mcbde4efc', 'Pain and fever', 'Morphine', '10 mg tablet', '', '', '', '', 1),
('Md56e1c00', 'Diabetes and endocrine', 'Metformin', '500 mg tablet', '', '', '', '', 1),
('Me0a48e9f', 'Cardiovascular', 'Atorvastatin', '10 mg tablet', '', '', '', '', 1),
('Me63f59c4', 'Pain and fever', 'Paracetamol', '500 mg tablet', '', '', '', '', 1),
('Me75119c1', 'Antibiotics', 'Nitrofurantoin', '50 mg tablet', '', '', '', '', 1),
('Mf0a5891c', 'Pain and fever', 'Diclofenac', '25 mg tablet', '', '', '', '', 1),
('Mf1e04b36', 'Pain and fever', 'Ibuprofen', '200 mg tablet', '', '', '', '', 1),
('Mf90931ed', 'Cardiovascular', 'Acetylsalicylic acid (Aspirin)', '80 mg tablet', '', '', '', '', 1);

-- --------------------------------------------------------

--
-- Tabelstructuur voor tabel `occupancy_snapshots`
--

CREATE TABLE `occupancy_snapshots` (
  `snapshot_date` date NOT NULL,
  `room_id` int(11) NOT NULL,
  `dept` varchar(40) NOT NULL,
  `beds` int(11) NOT NULL,
  `occ` int(11) NOT NULL,
  `patients` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tabelstructuur voor tabel `patients`
--

CREATE TABLE `patients` (
  `id` varchar(20) NOT NULL,
  `status` varchar(20) NOT NULL DEFAULT 'admitted',
  `department` varchar(40) NOT NULL DEFAULT '',
  `room_id` int(11) DEFAULT NULL,
  `room_num` varchar(20) DEFAULT NULL,
  `gender` varchar(30) DEFAULT NULL,
  `admit_date` datetime DEFAULT NULL,
  `discharge_date` datetime DEFAULT NULL,
  `data_rot47` longtext NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tabelstructuur voor tabel `rooms`
--

CREATE TABLE `rooms` (
  `id` int(11) NOT NULL,
  `num` varchar(20) NOT NULL,
  `dept` varchar(40) NOT NULL,
  `beds` int(11) NOT NULL DEFAULT 1,
  `occ` int(11) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Gegevens worden geëxporteerd voor tabel `rooms`
--

INSERT INTO `rooms` (`id`, `num`, `dept`, `beds`, `occ`) VALUES
(1, '101', 'emergency', 4, 0),
(2, '102', 'emergency', 4, 0),
(3, '201', 'cardiology', 3, 0),
(4, '202', 'cardiology', 3, 0),
(5, '301', 'pediatrics', 4, 0),
(6, '302', 'pediatrics', 4, 0),
(7, '401', 'icu', 2, 0),
(8, '402', 'icu', 2, 0),
(9, '501', 'surgery', 3, 0),
(10, '502', 'surgery', 3, 0);

-- --------------------------------------------------------

--
-- Tabelstructuur voor tabel `telephones`
--

CREATE TABLE `telephones` (
  `id` int(11) NOT NULL,
  `room_id` int(11) NOT NULL,
  `room_num` varchar(20) DEFAULT NULL,
  `number` varchar(60) NOT NULL,
  `ext` varchar(20) DEFAULT NULL,
  `purpose` varchar(120) DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `created` datetime DEFAULT NULL,
  `updated` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Tabelstructuur voor tabel `users`
--

CREATE TABLE `users` (
  `user` varchar(60) NOT NULL,
  `pass` varchar(255) NOT NULL,
  `role` varchar(30) NOT NULL,
  `mfa` tinyint(1) NOT NULL DEFAULT 0,
  `secret` varchar(64) NOT NULL DEFAULT '',
  `name` varchar(120) DEFAULT NULL,
  `email` varchar(160) DEFAULT NULL,
  `created` datetime DEFAULT NULL,
  `last_login` datetime DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Gegevens worden geëxporteerd voor tabel `users`
--

INSERT INTO `users` (`user`, `pass`, `role`, `mfa`, `secret`, `name`, `email`, `created`, `last_login`, `active`) VALUES
('admin', '$2y$12$9YFoxZIPaOauIDi6MA5uVeUgJ0EKctyOtQR.XvB1iFSoymFtME.Vy', 'admin', 1, 'FAFRXLZJG3BMRJB2', 'System Administrator', 'admin@hospital.org', '2026-10-20 15:11:10', '2026-10-20 15:31:46', 1),
('doctor', '$2y$12$66ovQmjIZ5qBsEJnSkk.4u1AdbzGTSpXvt4DuxfYjpmGGiUeNfiaK', 'doctor', 1, 'HY5KIRJDDYFRF3PW', 'John Smith, MD', 'doctor@hospital.org', '2026-10-20 15:11:11', NULL, 1),
('nurse', '$2y$12$sZi34hgiQc/5NvhR7o0vZu5k/toRUuRZC6dp007qBpnoarYw9ATMm', 'nurse', 1, '4V3WIUFOPSI5PYTY', 'Sarah Johnson, RN', 'nurse@hospital.org', '2026-10-20 15:11:11', NULL, 1),
('reception', '$2y$12$RYXiFXnaAfrblhiZsKv.8ONMQlVLmYVB8ABZfOT4whsjk4fFRs6oO', 'reception', 1, 'GM7EKMGGREZEZNQ7', 'Maria Garcia', 'reception@hospital.org', '2026-10-20 15:11:11', NULL, 1);

-- --------------------------------------------------------

--
-- Stand-in structuur voor view `v_all_stays`
-- (Zie onder voor de actuele view)
--
CREATE TABLE `v_all_stays` (
`id` varchar(20)
,`department` varchar(40)
,`room_id` int(11)
,`room_num` varchar(20)
,`gender` varchar(30)
,`admit_date` datetime
,`discharge_date` datetime
,`status` varchar(20)
,`src` varchar(8)
);

-- --------------------------------------------------------

--
-- Structuur voor de view `v_all_stays`
--
DROP TABLE IF EXISTS `v_all_stays`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_all_stays`  AS SELECT `patients`.`id` AS `id`, `patients`.`department` AS `department`, `patients`.`room_id` AS `room_id`, `patients`.`room_num` AS `room_num`, `patients`.`gender` AS `gender`, `patients`.`admit_date` AS `admit_date`, `patients`.`discharge_date` AS `discharge_date`, `patients`.`status` AS `status`, 'current' AS `src` FROM `patients`union all select `detached_patients`.`id` AS `id`,`detached_patients`.`department` AS `department`,`detached_patients`.`room_id` AS `room_id`,`detached_patients`.`room_num` AS `room_num`,`detached_patients`.`gender` AS `gender`,`detached_patients`.`admit_date` AS `admit_date`,`detached_patients`.`discharge_date` AS `discharge_date`,`detached_patients`.`status` AS `status`,'detached' AS `src` from `detached_patients`  ;

--
-- Indexen voor geëxporteerde tabellen
--

--
-- Indexen voor tabel `activity_log`
--
ALTER TABLE `activity_log`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_l_time` (`logged_at`),
  ADD KEY `idx_l_type_time` (`type`,`logged_at`),
  ADD KEY `idx_l_user_time` (`username`,`logged_at`),
  ADD KEY `idx_l_patient` (`patient_id`,`logged_at`);

--
-- Indexen voor tabel `app_kv`
--
ALTER TABLE `app_kv`
  ADD PRIMARY KEY (`k`);

--
-- Indexen voor tabel `detached_patients`
--
ALTER TABLE `detached_patients`
  ADD PRIMARY KEY (`id`,`discharge_date`),
  ADD KEY `idx_d_week` (`archive_week`),
  ADD KEY `idx_d_discharge` (`discharge_date`),
  ADD KEY `idx_d_dept_admit` (`department`,`admit_date`),
  ADD KEY `idx_d_photos` (`photos_deleted`);

--
-- Indexen voor tabel `detach_runs`
--
ALTER TABLE `detach_runs`
  ADD PRIMARY KEY (`run_id`);

--
-- Indexen voor tabel `medications`
--
ALTER TABLE `medications`
  ADD PRIMARY KEY (`id`);

--
-- Indexen voor tabel `occupancy_snapshots`
--
ALTER TABLE `occupancy_snapshots`
  ADD PRIMARY KEY (`snapshot_date`,`room_id`),
  ADD KEY `idx_s_dept` (`dept`,`snapshot_date`);

--
-- Indexen voor tabel `patients`
--
ALTER TABLE `patients`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_p_status_discharge` (`status`,`discharge_date`),
  ADD KEY `idx_p_room` (`room_id`),
  ADD KEY `idx_p_dept_admit` (`department`,`admit_date`);

--
-- Indexen voor tabel `rooms`
--
ALTER TABLE `rooms`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_room_num` (`num`),
  ADD KEY `idx_r_dept` (`dept`);

--
-- Indexen voor tabel `telephones`
--
ALTER TABLE `telephones`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_t_room` (`room_id`);

--
-- Indexen voor tabel `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`user`);

--
-- AUTO_INCREMENT voor geëxporteerde tabellen
--

--
-- AUTO_INCREMENT voor een tabel `activity_log`
--
ALTER TABLE `activity_log`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT voor een tabel `detach_runs`
--
ALTER TABLE `detach_runs`
  MODIFY `run_id` int(11) NOT NULL AUTO_INCREMENT;

DELIMITER $$
--
-- Gebeurtenissen
--
CREATE DEFINER=`root`@`localhost` EVENT `ev_weekly_detach` ON SCHEDULE EVERY 1 WEEK STARTS '2026-10-25 00:00:00' ON COMPLETION PRESERVE ENABLE COMMENT 'Weekly de-attach of discharged patients (Sunday 00:00)' DO CALL sp_detach_discharged(NOW(), 'event', @moved)$$

CREATE DEFINER=`root`@`localhost` EVENT `ev_daily_occupancy_snapshot` ON SCHEDULE EVERY 1 DAY STARTS '2026-10-20 23:55:00' ON COMPLETION PRESERVE ENABLE COMMENT 'Daily room occupancy snapshot' DO CALL sp_snapshot_occupancy(CURRENT_DATE)$$

DELIMITER ;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
