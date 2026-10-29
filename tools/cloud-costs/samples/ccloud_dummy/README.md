# ccloud_dummy

Dummy `confluent billing cost list --output json` data, one file per month (`<start date>_<end date>.json`), the way
`playground ccloud-costs-history` saves them for its HTML report. Every id and name is fake.

The story it tells: a cluster and a Stream Governance package billed every day, a few short-lived connectors of examples
every month, a Flink compute pool tried twice, a test cluster used for a week in a second environment, and an Oracle
XStream connector forgotten since Oct 10 that is still billing ($86.40 a day).

```bash
playground ccloud-costs-history --sample ccloud_dummy
playground ccloud-costs --sample ccloud_dummy   # last month only
```

It is also the report of the gallery of the documentation (`docs/reports.md`).
