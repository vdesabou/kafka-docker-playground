# aws_dummy

Dummy `aws ce get-cost-and-usage` data (grouped by `SERVICE` and `USAGE_TYPE`, `UnblendedCost` and `UsageQuantity`),
one file per month (`<start date>_<end date>.json`), plus `s3-buckets.json`, the way
`playground cloud-resources aws costs-history` saves them for its HTML report. Every name is fake.

The story it tells: a bucket of large 3rd-party artifacts in us-east-1, moved to Standard-IA by a lifecycle rule and
without access logging, downloaded more and more every month from the Internet and, since the third month, by
something running in us-west-2. Almost all the S3 cost is data sent out and Standard-IA retrieval fees, storage is
about $1 a month. Next to it, a small bucket of sink tests in eu-west-3, an empty bucket, and an EC2 instance of the
playground started a few days some months.

```bash
playground cloud-resources aws costs-history --sample aws_dummy
```
