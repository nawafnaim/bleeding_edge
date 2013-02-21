// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef LIB_INVOCATION_MIRROR_H_
#define LIB_INVOCATION_MIRROR_H_

#include "vm/allocation.h"

namespace dart {

class InvocationMirror : public AllStatic {
 public:
  // These enum correspond to the constants in invocation_mirror_patch.dart.
  // It is used to communicate the reason for statically thrown
  // NoSuchMethodErrors by the compiler.
  enum Type {
    // Constants describing the invocation type.
    // kField cannot be generated by regular invocation mirrors.
    kMethod = 0,
    kGetter = 1,
    kSetter = 2,
    kField  = 3,
    kTypeShift = 0,
    kTypeBits = 2,
    kTypeMask = (1 << kTypeBits) - 1
  };

  enum Call {
    // These values, except kDynamic, are only used when throwing
    // NoSuchMethodError for compile-time resolution failures.
    kDynamic = 0,
    kStatic  = 1,
    kConstructor = 2,
    kTopLevel = 3,
    kCallShift = kTypeBits,
    kCallBits = 2,
    kCallMask = (1 << kCallBits) - 1
  };

  static int EncodeType(Call call, Type type) {
    return (call << kCallShift) | type;
  }
};

}  // namespace dart

#endif  // LIB_INVOCATION_MIRROR_H_
