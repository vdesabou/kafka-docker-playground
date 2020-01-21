/**
 * Copyright © 2017 Jeremy Custenborder (jcustenborder@gmail.com)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.github.jcustenborder.vertica;

import com.google.common.base.Strings;

public class QueryBuilder {
  final VerticaStreamWriterBuilder streamWriterBuilder;

  public QueryBuilder(VerticaStreamWriterBuilder streamWriterBuilder) {
    this.streamWriterBuilder = streamWriterBuilder;
  }

  @Override
  public String toString() {
    StringBuilder builder = new StringBuilder();
    builder.append("COPY");
    builder.append(" ");

    if (!Strings.isNullOrEmpty(this.streamWriterBuilder.schema())) {
      builder.append('"');
      builder.append(this.streamWriterBuilder.schema());
      builder.append('"');
      builder.append(".");
    }
    builder.append('"');
    builder.append(this.streamWriterBuilder.table());
    builder.append('"');

    builder.append(" FROM STDIN");
    builder.append(" ");
    builder.append(streamWriterBuilder.compressionType());

    switch (this.streamWriterBuilder.streamWriterType()) {
      case NATIVE:
        builder.append(' ');
        builder.append(this.streamWriterBuilder.streamWriterType());
        break;
    }

    builder.append(' ');
    builder.append(this.streamWriterBuilder.loadMethod());

    builder.append(" REJECTED DATA '/tmp/copyLocal.rejected' EXCEPTIONS '/tmp/copyLocal.exceptions'");

    return builder.toString();
  }
}
