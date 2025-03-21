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

import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.auth.StsAssumeRoleCredentialsProvider;
import software.amazon.awssdk.services.sts.model.AssumeRoleRequest;

public class AwsAssumeRoleCredentialsProvider implements AwsCredentialsProvider {

  private String roleArn;
  private String roleExternalId;
  private String roleSessionName;

  private static StsAssumeRoleCredentialsProvider stsCredentialProvider;

  public static AwsCredentialsProvider create() {
    String accessKeyId = System.getenv("AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID");
    String secretKey = System.getenv("AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY");
    String roleArn = System.getenv("AWS_STS_ROLE_ARN");
    String roleSessionName = System.getenv("AWS_STS_SESSION_NAME");
    String roleExternalId = System.getenv("AWS_STS_EXTERNAL_ID");

    AwsBasicCredentials basicCredentials = AwsBasicCredentials.create(accessKeyId, secretKey);
      
    return StsAssumeRoleCredentialsProvider
          .builder()
          .stsClient(StsClient.builder()
              .credentialsProvider(StaticCredentialsProvider.create(basicCredentials))
              .build())
          .refreshRequest(() -> AssumeRoleRequest.builder()
              .roleArn(roleArn)
              .roleSessionName(roleSessionName)
              .externalId(roleExternalId)
              .build())
          .build();
  }

  @Override
  public AwsCredentials resolveCredentials() {
    return stsCredentialProvider.resolveCredentials();
  }
}