SELECT
  data_type,
  COUNT(*) AS column_count
FROM
  `db_name.INFORMATION_SCHEMA.COLUMNS`
GROUP BY
  data_type