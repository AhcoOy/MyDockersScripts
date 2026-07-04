-- role for the subproject (idempotent)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '__PHP_ID_____SUB_PROJECT_ID__') THEN
        CREATE ROLE "__PHP_ID_____SUB_PROJECT_ID__"
            LOGIN PASSWORD '__PHP_ID_____SUB_PROJECT_ID__';
    END IF;
END
$$;

-- database for the subproject (idempotent, needs psql \gexec)
SELECT 'CREATE DATABASE "__PHP_ID_____SUB_PROJECT_ID__" OWNER "__PHP_ID_____SUB_PROJECT_ID__"'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '__PHP_ID_____SUB_PROJECT_ID__')\gexec

GRANT ALL PRIVILEGES ON DATABASE "__PHP_ID_____SUB_PROJECT_ID__" TO "__PHP_ID_____SUB_PROJECT_ID__";

-- one schema per app, same name as the user; the default search_path
-- ("$user", public) resolves it first, and frameworks (e.g. CakePHP)
-- can set 'schema' to the same value as the credentials
\connect "__PHP_ID_____SUB_PROJECT_ID__"
CREATE SCHEMA IF NOT EXISTS "__PHP_ID_____SUB_PROJECT_ID__" AUTHORIZATION "__PHP_ID_____SUB_PROJECT_ID__";

-- matching schema for the project user in the project database
\connect "__PROJECT__"
CREATE SCHEMA IF NOT EXISTS "__PROJECT__" AUTHORIZATION "__PROJECT__";
