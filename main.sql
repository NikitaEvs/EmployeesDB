-- Create a schema
create schema if not exists employees;
set search_path to employees;

-- Create a table
drop table if exists relations;
create table if not exists relations
(
    id      serial primary key,
    boss_id integer,
    name    text
);

-- Populate a table with data
copy relations (id, boss_id, name)
    from program 'curl https://raw.githubusercontent.com/kostja/shad/main/homework/graph.csv'
    delimiter ',' csv;

-- Adjust serial column value
select setval(pg_get_serial_sequence('employees.relations', 'id'), max(id))
from relations;

-- 1. Add an employee

create or replace function add_employee(name text)
    returns void
as
$$
    insert into relations(boss_id, name) values (-1, name);
$$ language sql;

create or replace function add_employee_with_boss(name text, boss_id integer)
    returns void
as
$$
    insert into relations(boss_id, name) values (boss_id, name);
$$ language sql;

select add_employee('A');
select add_employee_with_boss('L', 1);

-- 2. Move employee from one department to another

create or replace function move_employee(employee_id integer, new_boss_id integer)
    returns void
as
$$
    update relations
    set boss_id = new_boss_id
    where id = employee_id;
$$ language sql;

select move_employee(13213, 2);

-- 3. Return a department

drop type if exists department cascade;
create type department as (boss text, employee_idx integer[], employee_names text[]);

create or replace function get_children(node_id integer)
    returns table(id integer, name text)
as
$$
    select id, name
    from  relations
    where boss_id = node_id;
$$ language sql;

select * from get_children(1);

create or replace function get_department(node_id integer)
    returns setof department
as
$$
    select (select name from relations where id = node_id), array_agg(id), array_agg(name)
    from get_children(node_id);
$$ language sql;

select * from get_department(1);

-- 4. Get all leaves

drop type if exists records cascade;
create type records as (id int, name text);

create or replace function get_leaves()
    returns setof records
as
$$
    select distinct relations.id, relations.name
    from relations left join relations r on relations.id = r.boss_id
    where r.boss_id is null;
$$ language sql;

select * from get_leaves();

-- 5. Get reporting list

drop type if exists reports cascade;
create type reports as (name text, report_ids integer[], report_names text[]);

create or replace function get_report_list(node_id integer)
    returns setof reports
as
$$
with recursive base as (
    select id, boss_id, name
    from relations
    where id = (select boss_id from relations where id = node_id)
    union all
    select step.id, step.boss_id, step.name
    from relations step
    join base on base.boss_id = step.id
)
select (select name from relations where id = node_id), array_agg(id), array_agg(name) from base;
$$ language sql;

select * from get_report_list(5);

-- 6. Get number of employees in the whole department

create or replace function get_number_of_employees_in_department(node_id integer)
    returns integer
as
$$
with recursive base(id, name) as (
    select id, name
    from relations
    where id = node_id
    union all
    select step.id, step.name
    from relations step
    join base on step.boss_id = base.id
)
select count(*) from base;
$$ language sql;

select * from get_number_of_employees_in_department(1);

-- 7. Anomaly detection

-- Detect cycles

drop type if exists cycle_report cascade;
create type cycle_report as (id_start integer, cycle_path json);

create or replace function detect_cycle()
    returns setof cycle_report
as
$$
with recursive base as (
    select id, name
    from relations
    union all
    select step.id, step.name
    from relations step
    join base on step.boss_id = base.id
) cycle id set is_cycle to true default false using cycle_path
select id, array_to_json(cycle_path) from base where is_cycle = true limit 1;
$$ language sql;

select * from detect_cycle();

-- Detect multiple employees without boss

create or replace function detect_more_than_one_employee_without_boss()
    returns bool
as
$$
    select case
        when (select count(*) from relations where boss_id = -1) > 1
            then true
        else false
        end;
$$ language sql;

select * from detect_more_than_one_employee_without_boss();

-- 8. Get rank of an employee

drop type if exists ranks cascade;
create type ranks as (name text, rank integer);

create or replace function get_rank(node_id integer)
    returns setof ranks
as
$$
with recursive base as (
    select id, boss_id, name
    from relations
    where id = (select boss_id from relations where id = node_id)
    union all
    select step.id, step.boss_id, step.name
    from relations step join base on base.boss_id = step.id
)
select (select name from relations where id = node_id), count(id) rank from base;
$$ language sql;

select * from get_rank(5);

-- 9. Get hierarchy in a graphical view

create or replace function print_hierarchy()
    returns table(hierarchy text)
as
$$
with recursive base(id, name, depth) as (
    select id, name, 0
    from relations
    where id = 1
    union all
    select step.id, step.name, depth + 1
    from relations step
    join base on step.boss_id = base.id
)
select repeat(' ', depth) || trim(name) from base order by depth;
$$ language sql;

select * from print_hierarchy();

-- 10. Get a path between two employees

create or replace function get_path(from_id integer, to_id integer)
    returns table(path integer[])
as
$$
    select
        case
            -- Catch corner case
            when from_id = to_id then null
            else (
                -- Main case

                -- Path from from_id to the root
                with f as (
                    select *, row_number() over () as num from (select unnest(report_ids) path from get_report_list( from_id)) path
                -- Path from to_id to the root
                ), s as (
                    select *, row_number() over () as num from (select unnest(report_ids) path from get_report_list(to_id)) path
                )
                select array_agg(path) from(
                    -- Path from from_to to root without main part
                    (
                        select f.path
                        from f left join s on f.path = s.path
                        where s.path is null
                        order by f.num
                    )
                    union all
                    -- The least common parent
                    (
                        select s.path
                        from s inner join f on s.path = f.path
                        order by s.num
                        limit 1
                    )
                    -- Path from the least common parent to the to_id
                    union all
                    (
                        select s.path
                        from s left join f on s.path = f.path
                        where f.path is null
                        order by s.num desc
                    )
                ) paths)
        end;
$$ language sql;

select * from get_path(223, 23131);
