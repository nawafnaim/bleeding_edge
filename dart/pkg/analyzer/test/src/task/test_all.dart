// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library test.src.task;

import 'package:unittest/unittest.dart';

import 'inputs_test.dart' as inputs_test;
import 'manager_test.dart' as manager_test;
import 'model_test.dart' as model_test;
import 'targets_test.dart' as targets_test;

/// Utility for manually running all tests.
main() {
  groupSep = ' | ';
  group('task tests', () {
    inputs_test.main();
    manager_test.main();
    model_test.main();
    targets_test.main();
  });
}
