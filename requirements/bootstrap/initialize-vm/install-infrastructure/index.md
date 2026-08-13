# Install infrastructure

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_initialize_vm_install_infrastructure",
	"role": "canonical spec for the second sub-step of Initialize VM — installing the CVM infrastructure (tables, triggers, indexes, view, seed row, cvm marker) into a fresh DB. Gated on the presence of the cvm table so revived DBs skip the install.",
	"status": "V1 spec — brief; sub-step is optional at runtime, gated on the presence of the cvm table"
}}
~~~

The second sub-step of [Initialize VM](https://www.puck.uno/requirements/bootstrap/initialize-vm/). `db:exec(schema)` runs the CVM DDL — bundled into the caspian binary — on the open connection. Creates every table, trigger, index, and view; runs the seed `insert into objects (primitive, user, persistent) values ('h', 1, 1)`; inserts the `cvm` marker row.

After this returns, the database is a valid CVM file: the user row exists as the reachability root, the `cvm` table marks the file as ours, and every constraint the schema declares is live.

**Optional — gated on the cvm table.** The sub-step inspects the DB before doing anything: if the `cvm` marker table is present, the DB is already an installed CVM file and this sub-step does nothing. If the table is absent, the DB is fresh and the full installation runs — every `create table`, the seed insert, the `cvm` marker row. Same code path for fresh and existing engines; the "did we already install?" check is what makes the sub-step self-idempotent. Anything else that goes wrong (partial install from a crashed prior run, a foreign table with a colliding name) raises loudly at the failing SQL statement, which is how you find out.
