// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef VM_COVERAGE_H_
#define VM_COVERAGE_H_

#include "vm/allocation.h"
#include "vm/flags.h"

namespace dart {

DECLARE_FLAG(charp, coverage_dir);

// Forward declarations.
class Class;
class Function;
template <typename T> class GrowableArray;
class Isolate;
class JSONArray;
class JSONStream;
class Library;
class Script;
class String;

class CoverageFilter : public ValueObject {
 public:
  virtual bool ShouldOutputCoverageFor(const Library& lib,
                                       const Script& script,
                                       const Class& cls,
                                       const Function& func) const = 0;
  virtual ~CoverageFilter() {}
};

class CodeCoverage : public AllStatic {
 public:
  static void Write(Isolate* isolate);
  static void PrintJSON(Isolate* isolate,
                        JSONStream* stream,
                        CoverageFilter* filter);

 private:
  static void PrintClass(const Library& lib,
                         const Class& cls,
                         const JSONArray& arr,
                         CoverageFilter* filter);
  static void CompileAndAdd(const Function& function,
                            const JSONArray& hits_arr,
                            const GrowableArray<intptr_t>& pos_to_line);
};

}  // namespace dart

#endif  // VM_COVERAGE_H_
