# Solution of the first homework for YSDA DB course

## Description
Implement basic graph operations using relational DBMS. All solutions are in the [main.sql](main.sql) file.

## Data model
Data is stored in the adjacency list model. According to [this benchmark](https://explainextended.com/2009/09/24/adjacency-list-vs-nested-sets-postgresql/) it is more efficient to use recursive CTE than nested sets data model.

So the schema is as following:
```
create table if not exists relations
(
    id      serial primary key,
    boss_id integer,
    name    text
);
```sql

## How to run
- Create a container with PostgreSQL using `docker-compose up -d`.
- Install postgresql-client-common and postgresql-client-<version>
- Run queries using psql: `psql -h 0.0.0.0 -p 5432  -U cat -f main.sql` (password: meow)

