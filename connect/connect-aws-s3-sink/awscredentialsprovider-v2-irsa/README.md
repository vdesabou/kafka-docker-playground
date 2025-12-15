# AWS IRSA (IAM Roles for Service Accounts) Credentials Provider for Kafka Connect

This example demonstrates how to use IRSA (IAM Roles for Service Accounts) with Kafka Connect in Amazon EKS environments where AWS credentials are not available as environment variables.

## Background

### Traditional Approach (Environment Variables)
The standard `AwsAssumeRoleCredentialsProvider` expects AWS credentials to be provided as environment variables:
- `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID`
- `AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY`

### IRSA Approach (EKS Service Accounts)
In EKS environments using IRSA, credentials work differently:
- **No static access keys** - credentials are temporary and automatically rotated
- **Service account token** - EKS mounts a signed OIDC token at `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
- **Automatic credential injection** - EKS mutating webhook automatically sets:
  - `AWS_WEB_IDENTITY_TOKEN_FILE`: Path to the service account token
  - `AWS_ROLE_ARN`: IAM role ARN associated with the Kubernetes service account
  - `AWS_ROLE_SESSION_NAME`: (optional) Session name

## How IRSA Works

1. **Kubernetes Service Account** is created and annotated with an IAM role ARN:
   ```yaml
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: kafka-connect-sa
     annotations:
       eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/KafkaConnectRole
   ```

2. **Pod uses the service account**:
   ```yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: kafka-connect
   spec:
     serviceAccountName: kafka-connect-sa
   ```

3. **EKS automatically injects**:
   - Mounts the OIDC token file
   - Sets environment variables
   - Application uses `WebIdentityTokenFileCredentialsProvider`

## Implementation

### AwsAssumeRoleIrsaCredentialsProvider

The `AwsAssumeRoleIrsaCredentialsProvider` class uses AWS SDK v2's `WebIdentityTokenFileCredentialsProvider`, which:
- Reads the OIDC token from the file system
- Exchanges the token for temporary AWS credentials via STS
- Automatically refreshes credentials before expiry

### Two Modes of Operation

#### Mode 1: Direct IRSA Authentication (Recommended)
Use the IAM role associated with the service account directly:

```java
WebIdentityTokenFileCredentialsProvider.create()
```

Required environment variables (auto-injected by EKS):
- `AWS_WEB_IDENTITY_TOKEN_FILE`
- `AWS_ROLE_ARN`

#### Mode 2: IRSA + Additional Role Assumption
Use IRSA to authenticate, then assume a different role:

```java
StsAssumeRoleCredentialsProvider
    .builder()
    .stsClient(StsClient.builder()
        .credentialsProvider(WebIdentityTokenFileCredentialsProvider.create())
        .build())
    .refreshRequest(() -> AssumeRoleRequest.builder()
        .roleArn(additionalRoleArn)
        .roleSessionName(sessionName)
        .build())
    .build();
```

Additional optional environment variables:
- `AWS_STS_ROLE_ARN`: Additional role to assume
- `AWS_STS_SESSION_NAME`: Session name for the assumed role
- `AWS_STS_EXTERNAL_ID`: External ID (if required by trust policy)

## Setup in EKS

### 1. Create IAM Role with Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE:sub": "system:serviceaccount:default:kafka-connect-sa",
          "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

### 2. Attach Necessary Policies

```bash
aws iam attach-role-policy \
  --role-name KafkaConnectRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonKinesisReadOnlyAccess
```

### 3. Create Service Account

```bash
kubectl create serviceaccount kafka-connect-sa
kubectl annotate serviceaccount kafka-connect-sa \
  eks.amazonaws.com/role-arn=arn:aws:iam::123456789012:role/KafkaConnectRole
```

### 4. Deploy Kafka Connect

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-connect
spec:
  template:
    spec:
      serviceAccountName: kafka-connect-sa
      containers:
      - name: kafka-connect
        image: confluentinc/cp-kafka-connect:latest
        env:
        - name: CONNECT_PLUGIN_PATH
          value: /usr/share/confluent-hub-components
```

### 5. Configure Connector

```json
{
  "connector.class": "io.confluent.connect.kinesis.KinesisSourceConnector",
  "kinesis.credentials.provider.class": "com.github.vdesabou.AwsAssumeRoleIrsaCredentialsProvider",
  "kinesis.stream": "my-stream",
  "kinesis.region": "us-east-1",
  ...
}
```

## Advantages of IRSA

1. **No Static Credentials**: No need to manage AWS access keys
2. **Automatic Rotation**: Credentials are temporary and automatically refreshed
3. **Fine-grained Permissions**: Each service account can have different IAM permissions
4. **Audit Trail**: Better CloudTrail logging with service account information
5. **Security**: Credentials never leave the Kubernetes cluster

## Comparison

| Feature | Environment Variables | IRSA |
|---------|----------------------|------|
| Credential Type | Static access keys | Temporary tokens |
| Rotation | Manual | Automatic |
| Storage | Kubernetes secrets | OIDC token file |
| EKS-specific | No | Yes |
| Security | Lower (static keys) | Higher (temporary) |
| Setup Complexity | Simple | Moderate |

## Troubleshooting

### Issue: "Unable to load credentials from WebIdentityTokenFileCredentialsProvider"

**Cause**: Token file not found or invalid

**Solution**:
```bash
# Verify token file exists
kubectl exec -it kafka-connect-pod -- ls -la /var/run/secrets/eks.amazonaws.com/serviceaccount/

# Check environment variables
kubectl exec -it kafka-connect-pod -- env | grep AWS
```

### Issue: "Not authorized to perform: sts:AssumeRoleWithWebIdentity"

**Cause**: IAM role trust policy doesn't match service account

**Solution**: Verify trust policy conditions match:
- OIDC provider URL
- Service account namespace and name
- Audience (usually "sts.amazonaws.com")

### Issue: Connector fails with "Access Denied"

**Cause**: IAM role lacks necessary permissions

**Solution**:
```bash
# Attach required policy
aws iam attach-role-policy \
  --role-name KafkaConnectRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonKinesisReadOnlyAccess
```

## Testing Locally

For local testing without EKS, you can simulate IRSA by:

1. Setting environment variables manually:
```bash
export AWS_WEB_IDENTITY_TOKEN_FILE=/tmp/token
export AWS_ROLE_ARN=arn:aws:iam::123456789012:role/TestRole
```

2. Generating a test token (not for production):
```bash
# This is just a placeholder - in real EKS, this is a signed OIDC token
echo "test-token" > /tmp/token
```

**Note**: Actual OIDC tokens are signed JWT tokens issued by the EKS OIDC provider and cannot be generated locally for testing.

## References

- [AWS SDK for Java v2 - WebIdentityTokenFileCredentialsProvider](https://sdk.amazonaws.com/java/api/latest/software/amazon/awssdk/auth/credentials/WebIdentityTokenFileCredentialsProvider.html)
- [EKS IAM Roles for Service Accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Kafka Connect on Kubernetes](https://docs.confluent.io/platform/current/installation/docker/operations/external-volumes.html)

## Additional Resources

- Example implementation: `awscredentialsprovider-v2-irsa/`
- Script: `kinesis-source-irsa.sh`
- Docker Compose: `docker-compose.plaintext.irsa.yml`
