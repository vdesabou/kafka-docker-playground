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

import com.amazonaws.auth.AWSCredentials;
import com.amazonaws.auth.AWSCredentialsProvider;
import org.apache.kafka.common.Configurable;
import org.apache.kafka.common.config.AbstractConfig;
import org.apache.kafka.common.config.ConfigDef;
import com.amazonaws.auth.BasicAWSCredentials;
import java.util.Map;
import com.amazonaws.auth.AWSStaticCredentialsProvider;
import org.apache.kafka.common.config.types.Password;

/**
 * Simple AWSStaticCredentialsProvider
 */
public class BasicAwsCredentialsProvider implements AWSCredentialsProvider, Configurable {

  public static final String ACCESS_KEY_ID_CONFIG = "aws.access.key.id";
  public static final String SECRET_KEY_ID_CONFIG = "aws.secret.key.id";

  private static final ConfigDef CONFIG_DEF = new ConfigDef()
      .define(
          ACCESS_KEY_ID_CONFIG,
          ConfigDef.Type.STRING,
          ConfigDef.Importance.HIGH,
          "The AWS access key that will be used"
      ).define(
          SECRET_KEY_ID_CONFIG,
          ConfigDef.Type.PASSWORD,
          ConfigDef.Importance.HIGH,
          "The AWS access key that will be used"
        );

  private BasicAWSCredentials basicCredentials;
  private AWSStaticCredentialsProvider provider;


  @Override
  public void configure(Map<String, ?> configs) {
    AbstractConfig config = new AbstractConfig(CONFIG_DEF, configs);
    final String accessKeyId = (String) configs.get(ACCESS_KEY_ID_CONFIG);
    final String secretKey = (String) configs.get(SECRET_KEY_ID_CONFIG);
    if (!accessKeyId.equals("") && !secretKey.equals("")) {
      basicCredentials = new BasicAWSCredentials(accessKeyId, secretKey);
      provider = new AWSStaticCredentialsProvider(basicCredentials);
    }
  }

  @Override
  public AWSCredentials getCredentials() {

    return provider.getCredentials();
  }

  @Override
  public void refresh() {
    if (provider != null) {
      provider.refresh();
    }
  }

}
