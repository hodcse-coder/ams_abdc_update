# Database master file

`ABDC_ERP.sql` in the project root is the single PostgreSQL structure file. Its header contains the configured database name, database username and password. These are database connection credentials, not application login credentials. The local file is excluded from Git because it contains the requested password.

Create an empty PostgreSQL 17 database, connect using the credentials in the header, and import with:

```powershell
psql -h HOST -p PORT -U USERNAME -d DATABASE -W -v ON_ERROR_STOP=1 -f ABDC_ERP.sql
```

Replace the connection placeholders with the header values. This imports 237 tables plus sequences, functions, views, indexes and constraints. It does not copy student records or application accounts, create database roles, or reset passwords. The backend initializes application defaults on startup using its existing initialization routines.

The executable structure comes from the current database, supplemented by missing legacy table definitions. Legacy batch, section, subject and period foreign keys reference the current masters. The optional legacy `section_groups` master supports the archived academic structures.

All 17 SQL files present at consolidation are preserved verbatim in inactive `ABDC_SOURCE_BEGIN` / `ABDC_SOURCE_END` blocks, with SHA256 checksums. These blocks preserve historical scripts and data migrations without executing them during a full import. `server/master-schema.js` extracts only the 14 existing startup migrations in their original order. Future database changes must update this master file rather than introduce separate SQL files.

Older one-off scripts in `scripts/` that reference previously absent root SQL files are historical utilities; use the master import for a new database.

Validation: restored the complete file into an isolated empty database and ran the startup migrations twice successfully. The temporary validation database was removed; existing application data was not changed.
