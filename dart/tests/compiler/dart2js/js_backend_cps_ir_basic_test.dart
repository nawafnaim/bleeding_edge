// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// VMOptions=-DUSE_CPS_IR=true

// Tests for basic functionality.

library basic_tests;

import 'js_backend_cps_ir.dart';

const List<TestEntry> tests = const [
  const TestEntry("""
foo(a, [b = "b"]) => b;
bar(a, {b: "b", c: "c"}) => c;
main() {
  foo(0);
  foo(1, 2);
  bar(3);
  bar(4, b: 5);
  bar(6, c: 7);
  bar(8, b: 9, c: 10);
}
""",
"""
function() {
  V.foo(0, "b");
  V.foo(1, 2);
  V.bar(3, "b", "c");
  V.bar(4, 5, "c");
  V.bar(6, "b", 7);
  V.bar(8, 9, 10);
  return null;
}"""),
  const TestEntry(
  """
foo(a) {
  return a;
}
main() {
  var a = 10;
  var b = 1;
  var t;
  t = a;
  a = b;
  b = t;
  print(a);
  print(b);
  print(b);
  print(foo(a));
}
  """,
  """
function() {
  var a, b;
  a = 10;
  b = 1;
  P.print(b);
  P.print(a);
  P.print(a);
  P.print(V.foo(b));
  return null;
}"""),
  const TestEntry(
  """
foo() { return 42; }
main() { return foo(); }
  """,
  """function() {
  return V.foo();
}"""),
  const TestEntry("main() {}"),
  const TestEntry("main() { return 42; }"),
  const TestEntry("main() { return; }", """
function() {
  return null;
}"""),
  // Constructor invocation
  const TestEntry("""
main() {
  print(new Set());
  print(new Set.from([1, 2, 3]));
}""", r"""
function() {
  P.print(P.Set_Set());
  P.print(P.Set_Set$from([1, 2, 3]));
  return null;
}"""),
  // Call synthetic constructor.
  const TestEntry("""
class C {}
main() {
  print(new C());
}"""),
  // Method invocation
  const TestEntry("""
main() {
  print(new DateTime.now().isBefore(new DateTime.now()));
}""", r"""
function() {
  P.print(P.DateTime$now().isBefore$1(P.DateTime$now()));
  return null;
}"""),
];


void main() {
  runTests(tests);
}
