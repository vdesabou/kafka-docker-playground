/*
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.github.vdesabou;

import software.amazon.awssdk.auth.credentials.AwsCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.WebIdentityTokenFileCredentialsProvider;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.auth.StsAssumeRoleCredentialsProvider;
import software.amazon.awssdk.services.sts.model.AssumeRoleRequest;

/**
 * AWS credentials provider for IRSA (IAM Roles for Service Accounts) in EKS.
 * 
 * This provider uses the WebIdentityTokenFileCredentialsProvider to authenticate
 * using the service account token mounted by EKS, then optionally assumes an
 * additional role if required.
 * 
 * Required Environment Variables (automatically set by EKS when using IRSA):
 * - AWS_WEB_IDENTITY_TOKEN_FILE: Path to the service account token file
 * - AWS_ROLE_ARN: The IAM role ARN associated with the service account
 * - AWS_REGION: AWS region (optional, defaults to us-east-1)
 * 
 * Optional Environment Variables (for assuming an additional role):
 * - AWS_STS_ROLE_ARN: Role ARN to assume after initial IRSA authentication
 * - AWS_STS_SESSION_NAME: Session name for the assumed role
 * - AWS_STS_EXTERNAL_ID: External ID for the assumed role (if required)
 */
public class AwsAssumeRoleIrsaCredentialsProvider implements AwsCredentialsProvider {

  private static AwsCredentialsProvider credentialsProvider;

  public static AwsCredentialsProvider create() {
    // Check if we need to assume an additional role beyond the IRSA role
    String additionalRoleArn = System.getenv("AWS_STS_ROLE_ARN");
    String roleSessionName = System.getenv("AWS_STS_SESSION_NAME");
    String roleExternalId = System.getenv("AWS_STS_EXTERNAL_ID");

    // WebIdentityTokenFileCredentialsProvider automatically reads these env vars:
    // - AWS_WEB_IDENTITY_TOKEN_FILE
    // - AWS_ROLE_ARN
    // - AWS_ROLE_SESSION_NAME (optional)
    WebIdentityTokenFileCredentialsProvider webIdentityProvider = 
        WebIdentityTokenFileCredentialsProvider.create();

    // If an additional role needs to be assumed, use STS to assume it
    if (additionalRoleArn != null && !additionalRoleArn.isEmpty()) {
      System.out.println("IRSA: Using WebIdentityTokenFileCredentialsProvider with additional role assumption");
      System.out.println("IRSA: Additional Role ARN: " + additionalRoleArn);
      
      return StsAssumeRoleCredentialsProvider
          .builder()
          .stsClient(StsClient.builder()
              .credentialsProvider(webIdentityProvider)
              .build())
          .refreshRequest(() -> {
              AssumeRoleRequest.Builder requestBuilder = AssumeRoleRequest.builder()
                  .roleArn(additionalRoleArn)
                  .roleSessionName(roleSessionName != null ? roleSessionName : "kafka-connect-session");
              
              if (roleExternalId != null && !roleExternalId.isEmpty()) {
                  requestBuilder.externalId(roleExternalId);
              }
              
              return requestBuilder.build();
          })
          .build();
    } else {
      // No additional role to assume, just use IRSA credentials directly
      System.out.println("IRSA: Using WebIdentityTokenFileCredentialsProvider directly");
      System.out.println("IRSA: Role ARN from service account: " + System.getenv("AWS_ROLE_ARN"));
      return webIdentityProvider;
    }
  }

  @Override
  public AwsCredentials resolveCredentials() {
    if (credentialsProvider == null) {
      credentialsProvider = create();
    }
    return credentialsProvider.resolveCredentials();
  }
}
