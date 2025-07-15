import os
from databricks import sql
import sys
from prettytable import PrettyTable # For formatted output

def run_databricks_cli():
    """
    Connects to Databricks using environment variables and provides an interactive SQL CLI.
    """
    # Retrieve Databricks connection details from environment variables
    server_hostname = os.getenv("DATABRICKS_SERVER_HOSTNAME")
    http_path = os.getenv("DATABRICKS_HTTP_PATH")
    access_token = os.getenv("DATABRICKS_ACCESS_TOKEN")

    # Basic validation for environment variables
    if not all([server_hostname, http_path, access_token]):
        print("Error: Please set DATABRICKS_SERVER_HOSTNAME, DATABRICKS_HTTP_PATH, and DATABRICKS_ACCESS_TOKEN environment variables.", file=sys.stderr)
        sys.exit(1)

    print("Attempting to connect to Databricks...")
    connection = None
    try:
        # Establish a connection to Databricks
        connection = sql.connect(
            server_hostname=server_hostname,
            http_path=http_path,
            access_token=access_token
        )
        print("Successfully connected to Databricks.")
        print("Type your SQL queries and press Enter. Type 'exit' or 'quit' to close.")

        while True:
            try:
                query = input("Databricks SQL> ").strip()
                if query.lower() in ["exit", "quit"]:
                    print("Exiting Databricks SQL CLI.")
                    break
                if not query:
                    continue

                with connection.cursor() as cursor:
                    print(f"Executing query: {query}")
                    cursor.execute(query)

                    # Fetch column names for header
                    columns = [desc[0] for desc in cursor.description]
                    
                    # Fetch all results
                    results = cursor.fetchall()

                    if results:
                        table = PrettyTable()
                        table.field_names = columns
                        for row in results:
                            table.add_row(row)
                        print(table)
                    else:
                        print("Query executed successfully, no results returned (e.g., DDL/DML statement).")

            except Exception as e:
                print(f"Error executing query: {e}", file=sys.stderr)
            except KeyboardInterrupt:
                print("\nExiting Databricks SQL CLI.")
                break

    except Exception as e:
        print(f"An error occurred during connection: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        if connection:
            connection.close()
            print("Connection to Databricks closed.")

if __name__ == "__main__":
    run_databricks_cli()
