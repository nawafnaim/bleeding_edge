/*
 * Copyright (c) 2014, the Dart project authors.
 * 
 * Licensed under the Eclipse Public License v1.0 (the "License"); you may not use this file except
 * in compliance with the License. You may obtain a copy of the License at
 * 
 * http://www.eclipse.org/legal/epl-v10.html
 * 
 * Unless required by applicable law or agreed to in writing, software distributed under the License
 * is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
 * or implied. See the License for the specific language governing permissions and limitations under
 * the License.
 */
package com.google.dart.server.internal.remote;

import com.google.common.base.Joiner;
import com.google.dart.engine.internal.context.AnalysisOptionsImpl;
import com.google.dart.engine.source.Source;
import com.google.dart.server.VersionConsumer;
import com.google.dart.server.internal.integration.RemoteAnalysisServerImplIntegrationTest;
import com.google.gson.JsonElement;
import com.google.gson.JsonParser;

/**
 * Unit tests for {@link RemoteAnalysisServerImpl}, for integration tests which actually uses the
 * remote server, see {@link RemoteAnalysisServerImplIntegrationTest}.
 */
public class RemoteAnalysisServerImplTest extends AbstractRemoteServerTest {

  public void test_getVersion() throws Exception {
    final String[] versionPtr = {null};
    server.getVersion(new VersionConsumer() {
      @Override
      public void computedVersion(String version) {
        versionPtr[0] = version;
      }
    });
    responseFromServer(parseJson(//
        "{",
        "  'id': '0',",
        "  'result': {",
        "    'version': '0.0.1'",
        "  }",
        "}").toString());
    server.test_waitForWorkerComplete();
    assertEquals("0.0.1", versionPtr[0]);
  }

  public void test_setOptions() throws Exception {
    server.setOptions("contextId", new AnalysisOptionsImpl());
    responseFromServer(parseJson(//
        "{",
        "  'id': '0'",
        "}").toString());
    server.test_waitForWorkerComplete();
  }

  public void test_setPrioritySources() throws Exception {
    String contextId = "id";
    Source source = addSource(contextId, "test.dart", makeSource(""));
    server.setPrioritySources(contextId, new Source[] {source});
    responseFromServer(parseJson(//
        "{",
        "  'id': '0'",
        "}").toString());
    server.test_waitForWorkerComplete();
  }

  public void test_shutdown() throws Exception {
    server.shutdown();
    responseFromServer(parseJson(//
        "{",
        "  'id': '0'",
        "}").toString());
    server.test_waitForWorkerComplete();
  }

  /**
   * Builds a JSON string from the given lines. Replaces single quotes with double quotes. Then
   * parses this string as a {@link JsonElement}.
   */
  private JsonElement parseJson(String... lines) {
    String json = Joiner.on('\n').join(lines);
    json = json.replace('\'', '"');
    return new JsonParser().parse(json);
  }

}