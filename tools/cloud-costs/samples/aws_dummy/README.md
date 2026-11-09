# aws_dummy

Dummy `aws ce get-cost-and-usage` data (grouped by `SERVICE` and `USAGE_TYPE`, `UnblendedCost` and `UsageQuantity`),
one file per month (`<start date>_<end date>.json`), plus `daily.json` (the same query per day over the last 60 days,
`--days`) and `s3-buckets.json`, the way
`playground cloud-resources aws costs-history` saves them for its HTML report. Every name is fake, and `--sample` shows
the tag of a fake user (`cflt_managed_id=kdp-dummy`).

The story it tells: a bucket of large 3rd-party artifacts in us-east-1, moved to Standard-IA by a lifecycle rule and
without access logging, downloaded more and more every month from the Internet and, since the third month, by
something running in us-west-2. Almost all the S3 cost is data sent out and Standard-IA retrieval fees, storage is
about $1 a month. Next to it, a small bucket of sink tests in eu-west-3, an empty bucket, and an EC2 instance of the
playground started a few days some months.

On 2026-10-14 the downloads of us-west-2 move to an ECR repository in us-west-2 (free there): the cost per day shows the
step (S3 to us-west-2 and the Standard-IA retrieval fees down, ECR data sent to the Internet up, the pulls of the
GitHub-hosted runners), and the ECR finding appears.

```bash
playground cloud-resources aws costs-history --sample aws_dummy
```

It is also the report of the gallery of the documentation (`docs/reports.md`).
