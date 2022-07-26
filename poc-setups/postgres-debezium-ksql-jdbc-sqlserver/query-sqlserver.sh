#!/bin/bash
set -e

echo "Show content of target table CUSTOMERS_FLAT in SQL Server:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
select * from CUSTOMERS_FLAT
GO
EOF
cat /tmp/result.log
