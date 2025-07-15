FROM python:3.9-slim-buster

WORKDIR /app

RUN pip install databricks-sql-connector[pyarrow] prettytable

COPY databricks_sql_cli.py .

CMD sleep infinity