// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart2js.test.message_kind_helper;

import 'package:expect/expect.dart';
import 'dart:async';

import '../../../sdk/lib/_internal/compiler/implementation/dart2jslib.dart' show
    Compiler,
    MessageKind;

import 'memory_compiler.dart';

const String ESCAPE_REGEXP = r'[[\]{}()*+?.\\^$|]';

/// Most examples generate a single diagnostic.
/// Add an exception here if a single diagnostic cannot be produced.
/// However, consider that a single concise diagnostic is easier to understand,
/// so try to change error reporting logic before adding an exception.
final Set<MessageKind> kindsWithExtraMessages = new Set<MessageKind>.from([
    // See http://dartbug.com/18361.
    MessageKind.CANNOT_EXTEND_MALFORMED,
    MessageKind.CANNOT_IMPLEMENT_MALFORMED,
    MessageKind.CANNOT_MIXIN,
    MessageKind.CANNOT_MIXIN_MALFORMED,
    MessageKind.CYCLIC_TYPEDEF_ONE,
    MessageKind.EQUAL_MAP_ENTRY_KEY,
    MessageKind.FINAL_FUNCTION_TYPE_PARAMETER,
    MessageKind.FORMAL_DECLARED_CONST,
    MessageKind.FORMAL_DECLARED_STATIC,
    MessageKind.HEX_DIGIT_EXPECTED,
    MessageKind.HIDDEN_IMPLICIT_IMPORT,
    MessageKind.HIDDEN_IMPORT,
    MessageKind.INHERIT_GETTER_AND_METHOD,
    MessageKind.UNIMPLEMENTED_METHOD,
    MessageKind.UNIMPLEMENTED_METHOD_ONE,
    MessageKind.UNTERMINATED_STRING,
    MessageKind.VAR_FUNCTION_TYPE_PARAMETER,
    MessageKind.VOID_NOT_ALLOWED,
    MessageKind.UNMATCHED_TOKEN,
]);

/// Most messages can be tested without causing a fatal error. Add an exception
/// here if a fatal error is unavoidable and leads to pending classes.
/// Try to avoid adding exceptions here; a fatal error causes the compiler to
/// stop before analyzing all input, and it isn't safe to reuse it.
final Set<MessageKind> kindsWithPendingClasses = new Set<MessageKind>.from([
    MessageKind.TYPEDEF_FORMAL_WITH_DEFAULT,
]);

/// Most messages can be tested without causing a fatal error. Add an exception
/// here if a fatal error is unavoidable.
/// Try to avoid adding exceptions here; a fatal error causes the compiler to
/// stop before analyzing all input, and it isn't safe to reuse it.
final Set<MessageKind> kindsWithFatalErrors = new Set<MessageKind>.from([
    MessageKind.FUNCTION_TYPE_FORMAL_WITH_DEFAULT,
    MessageKind.HEX_DIGIT_EXPECTED,
    MessageKind.REDIRECTING_FACTORY_WITH_DEFAULT,
    MessageKind.REFERENCE_IN_INITIALIZATION,
    MessageKind.TYPEDEF_FORMAL_WITH_DEFAULT,
    MessageKind.UNMATCHED_TOKEN,
    MessageKind.UNTERMINATED_STRING,
]);

Future<Compiler> check(MessageKind kind, Compiler cachedCompiler) {
  Expect.isNotNull(kind.howToFix);
  Expect.isFalse(kind.examples.isEmpty);

  return Future.forEach(kind.examples, (example) {
    if (example is String) {
      example = {'main.dart': example};
    } else {
      Expect.isTrue(example is Map,
                    "Example must be either a String or a Map.");
      Expect.isTrue(example.containsKey('main.dart'),
                    "Example map must contain a 'main.dart' entry.");
    }
    List<String> messages = <String>[];
    void collect(Uri uri, int begin, int end, String message, kind) {
      if (kind.name == 'verbose info' || kind.name == 'info') {
        return;
      }
      messages.add(message);
    }

    Compiler compiler = compilerFor(
        example,
        diagnosticHandler: collect,
        options: ['--analyze-only'],
        cachedCompiler: cachedCompiler);

    return compiler.run(Uri.parse('memory:main.dart')).then((_) {

      Expect.isFalse(messages.isEmpty, 'No messages in """$example"""');

      String expectedText = !kind.hasHowToFix
          ? kind.template : '${kind.template}\n${kind.howToFix}';
      String pattern = expectedText.replaceAllMapped(
          new RegExp(ESCAPE_REGEXP), (m) => '\\${m[0]}');
      pattern = pattern.replaceAll(new RegExp(r'#\\\{[^}]*\\\}'), '.*');

      // TODO(johnniwinther): Extend MessageKind to contain information on
      // where info messages are expected.
      bool messageFound = false;
      List unexpectedMessages = [];
      for (String message in messages) {
        if (!messageFound && new RegExp('^$pattern\$').hasMatch(message)) {
          messageFound = true;
        } else {
          unexpectedMessages.add(message);
        }
      }
      Expect.isTrue(messageFound, '"$pattern" does not match any in $messages');
      Expect.isFalse(compiler.hasCrashed);
      if (!unexpectedMessages.isEmpty) {
        for (String message in unexpectedMessages) {
          print("Unexpected message: $message");
        }
        if (!kindsWithExtraMessages.contains(kind)) {
          // Try changing the error reporting logic before adding an exception
          // to [kindsWithExtraMessages].
          throw 'Unexpected messages found.';
        }
      }
      cachedCompiler = compiler;
      Expect.isTrue(kindsWithFatalErrors.contains(kind) ||
                    !compiler.compilerWasCancelled);

      bool pendingStuff = false;
      for (var e in compiler.resolver.pendingClassesToBePostProcessed) {
        pendingStuff = true;
        compiler.reportInfo(
            e, MessageKind.GENERIC,
            {'text': 'Pending class to be post-processed.'});
      }
      for (var e in compiler.resolver.pendingClassesToBeResolved) {
        pendingStuff = true;
        compiler.reportInfo(
            e, MessageKind.GENERIC,
            {'text': 'Pending class to be resolved.'});
      }
      if (pendingStuff) {
        if (!kindsWithPendingClasses.contains(kind)) {
          throw 'Stuff was pending';
        }
        cachedCompiler = null;
      } else if (compiler.compilerWasCancelled) {
        cachedCompiler = null;
      } else {
        cachedCompiler = compiler;
      }
    });
  }).then((_) => cachedCompiler);
}
