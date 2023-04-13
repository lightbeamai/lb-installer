import os
from typing import Iterator

import psycopg2
import pandas as pd
from sqlalchemy import create_engine

PG_USER = os.getenv("PG_USER")
PG_PASSWORD = os.getenv("PG_PASSWORD")
PG_HOST = os.getenv("PG_HOST")
PG_PORT = os.getenv("PG_PORT")
PG_DATABASE = os.getenv("PG_DATABASE")
SF_USER = os.getenv("SF_USER")
SF_PASSWORD = os.getenv("SF_PASSWORD")
SF_ACCOUNT = os.getenv("SF_ACCOUNT")


def main():
    sf_conn_string = f"snowflake://{SF_USER}:{SF_PASSWORD}@{SF_ACCOUNT}/"
    sf_engine = create_engine(sf_conn_string)
    sf_connection = sf_engine.connect()
    sf_connection.execute(f"DROP DATABASE IF EXISTS {PG_DATABASE}").fetchall()
    sf_connection.execute(f"CREATE DATABASE {PG_DATABASE}").fetchall()
    sf_connection.close()
    sf_conn_string = f"snowflake://{SF_USER}:{SF_PASSWORD}@{SF_ACCOUNT}/{PG_DATABASE}"
    sf_engine = create_engine(sf_conn_string)
    sf_connection = sf_engine.connect()
    conn = psycopg2.connect(host=PG_HOST, dbname=PG_DATABASE, user=PG_USER, password=PG_PASSWORD, port=PG_PORT)
    cursor = conn.cursor()
    cursor.execute("""SELECT table_name, table_schema FROM information_schema.tables
           WHERE table_schema = 'public'""")
    for table in cursor.fetchall():
        table_name = table[0]
        table_schema = table[1]
        print(f"{table_schema}.{table_name}")
        dfs: Iterator[pd.DataFrame] = pd.read_sql(f"select * from {table_schema}.{table_name}", conn, chunksize=10000)
        for idx, df in enumerate(dfs):
            mode = "append"
            if idx == 0:
                mode = "replace"
            df: pd.DataFrame = df
            df.to_sql(table_name, sf_connection, table_schema, if_exists=mode, index=False)


if __name__ == '__main__':
    main()