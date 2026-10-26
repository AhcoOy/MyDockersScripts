-- Runs on the HOST's MariaDB (shared by every LAlMP project), as its admin.
-- Every user exists for three hosts, because the server matches a client by
-- its literal address:
--   '__NET_PREFIX__.%'  this project's containers (a native Docker Engine
--                       keeps their own 172.30.N.x source address)
--   '127.0.0.1'         TCP from this machine, and Docker Desktop, which
--                       forwards container connections from the loopback
--   'localhost'         the unix socket (host phpMyAdmin, plain `mariadb`)
-- Grants stay scoped to this subproject's database — never *.* on a shared
-- server.

CREATE DATABASE IF NOT EXISTS `__DB_NAME__`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '__DB_NAME__'@'__NET_PREFIX__.%' IDENTIFIED BY '__DB_NAME__';
CREATE USER IF NOT EXISTS '__DB_NAME__'@'127.0.0.1' IDENTIFIED BY '__DB_NAME__';
CREATE USER IF NOT EXISTS '__DB_NAME__'@'localhost' IDENTIFIED BY '__DB_NAME__';
GRANT ALL PRIVILEGES ON `__DB_NAME__`.* TO '__DB_NAME__'@'__NET_PREFIX__.%';
GRANT ALL PRIVILEGES ON `__DB_NAME__`.* TO '__DB_NAME__'@'127.0.0.1';
GRANT ALL PRIVILEGES ON `__DB_NAME__`.* TO '__DB_NAME__'@'localhost';

-- project user (host phpMyAdmin login) sees every subproject database
CREATE USER IF NOT EXISTS '__PROJECT__'@'__NET_PREFIX__.%' IDENTIFIED BY '__PROJECT__';
CREATE USER IF NOT EXISTS '__PROJECT__'@'127.0.0.1' IDENTIFIED BY '__PROJECT__';
CREATE USER IF NOT EXISTS '__PROJECT__'@'localhost' IDENTIFIED BY '__PROJECT__';
GRANT ALL PRIVILEGES ON `__DB_NAME__`.* TO '__PROJECT__'@'__NET_PREFIX__.%';
GRANT ALL PRIVILEGES ON `__DB_NAME__`.* TO '__PROJECT__'@'127.0.0.1';
GRANT ALL PRIVILEGES ON `__DB_NAME__`.* TO '__PROJECT__'@'localhost';

FLUSH PRIVILEGES;
