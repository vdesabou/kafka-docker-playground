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

import org.apache.kafka.common.Configurable;

import java.util.Collections;
import java.util.Map;

import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.auth.StsAssumeRoleCredentialsProvider;
import software.amazon.awssdk.services.sts.model.AssumeRoleRequest;

public class AwsAssumeRoleCredentialsProvider implements AwsCredentialsProvider, Configurable {

    public static final String ROLE_EXTERNAL_ID_CONFIG = "sts.role.external.id";
    public static final String ROLE_ARN_CONFIG = "sts.role.arn";
    public static final String ROLE_SESSION_NAME_CONFIG = "sts.role.session.name";
    public static final String ACCESS_KEY_ID_CONFIG = "sts.aws.access.key.id";
    public static final String SECRET_KEY_ID_CONFIG = "sts.aws.secret.key.id";

    private static final String ACCESS_KEY_ID_ENV = "AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID";
    private static final String SECRET_ACCESS_KEY_ENV = "AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY";
    private static final String ROLE_ARN_ENV = "AWS_STS_ROLE_ARN";
    private static final String ROLE_SESSION_NAME_ENV = "AWS_STS_SESSION_NAME";
    private static final String ROLE_EXTERNAL_ID_ENV = "AWS_STS_EXTERNAL_ID";
    private static final String DEFAULT_ROLE_SESSION_NAME = "kafka-connect-session";

    private volatile StsAssumeRoleCredentialsProvider stsCredentialProvider;

    public static AwsCredentialsProvider create() {
        // Return this class instance so connectors can call
        // Configurable.configure(configs).
        return new AwsAssumeRoleCredentialsProvider();
    }

    @Override
    public void configure(Map<String, ?> configs) {
        Map<String, ?> safeConfigs = configs == null ? Collections.emptyMap() : configs;

        String accessKeyId = firstNonBlank(
                asString(safeConfigs.get(ACCESS_KEY_ID_CONFIG)),
                System.getenv(ACCESS_KEY_ID_ENV));
        String secretKey = firstNonBlank(
                asString(safeConfigs.get(SECRET_KEY_ID_CONFIG)),
                System.getenv(SECRET_ACCESS_KEY_ENV));
        String roleArn = firstNonBlank(
                asString(safeConfigs.get(ROLE_ARN_CONFIG)),
                System.getenv(ROLE_ARN_ENV));
        String roleSessionName = firstNonBlank(
                asString(safeConfigs.get(ROLE_SESSION_NAME_CONFIG)),
                System.getenv(ROLE_SESSION_NAME_ENV),
                DEFAULT_ROLE_SESSION_NAME);
        String roleExternalId = firstNonBlank(
                asString(safeConfigs.get(ROLE_EXTERNAL_ID_CONFIG)),
                System.getenv(ROLE_EXTERNAL_ID_ENV));

        AssumeRoleRequest.Builder assumeRoleRequestBuilder = AssumeRoleRequest.builder()
                .roleArn(roleArn)
                .roleSessionName(roleSessionName);
        if (isNotBlank(roleExternalId)) {
            assumeRoleRequestBuilder.externalId(roleExternalId);
        }

        StsClient stsClient;
        if (isNotBlank(accessKeyId) && isNotBlank(secretKey)) {
            AwsBasicCredentials basicCredentials = AwsBasicCredentials.create(accessKeyId, secretKey);
            stsClient = StsClient.builder()
                    .credentialsProvider(StaticCredentialsProvider.create(basicCredentials))
                    .build();
        } else {
            // Default STS client uses the AWS SDK v2 default credentials provider chain.
            stsClient = StsClient.create();
        }

        stsCredentialProvider = StsAssumeRoleCredentialsProvider
                .builder()
                .stsClient(stsClient)
                .refreshRequest(assumeRoleRequestBuilder.build())
                .build();
    }

    @Override
    public AwsCredentials resolveCredentials() {
        if (stsCredentialProvider == null) {
            // Fallback for connectors that do not call Configurable.configure().
            configure(Collections.emptyMap());
        }
        return stsCredentialProvider.resolveCredentials();
    }

    private static String asString(Object value) {
        if (value == null) {
            return null;
        }
        return value.toString();
    }

    private static boolean isNotBlank(String value) {
        return value != null && !value.trim().isEmpty();
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            if (isNotBlank(value)) {
                return value;
            }
        }
        return null;
    }
}