


SELECT typname 
FROM pg_type 
WHERE typtype = 'e'
ORDER BY typname;






SELECT version();





WITH enums AS (
    SELECT 
        t.typname AS enum_name,
        e.enumlabel AS enum_value,
        e.enumsortorder
    FROM pg_type t
    JOIN pg_enum e ON t.oid = e.enumtypid
    WHERE t.typtype = 'e'
    ORDER BY t.typname, e.enumsortorder
)
SELECT 
    enum_name,
    array_agg(enum_value ORDER BY enumsortorder) AS enum_values
FROM enums
GROUP BY enum_name
ORDER BY enum_name;