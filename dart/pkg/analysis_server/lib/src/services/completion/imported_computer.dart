// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library services.completion.computer.dart.toplevel;

import 'dart:async';
import 'dart:collection';

import 'package:analysis_server/src/protocol_server.dart' hide Element,
    ElementKind;
import 'package:analysis_server/src/services/completion/dart_completion_cache.dart';
import 'package:analysis_server/src/services/completion/dart_completion_manager.dart';
import 'package:analysis_server/src/services/completion/optype.dart';
import 'package:analysis_server/src/services/completion/suggestion_builder.dart';
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/element.dart';

/**
 * A computer for calculating imported class and top level variable
 * `completion.getSuggestions` request results.
 */
class ImportedComputer extends DartCompletionComputer {
  bool shouldWaitForLowPrioritySuggestions;
  _ImportedSuggestionBuilder builder;

  ImportedComputer({this.shouldWaitForLowPrioritySuggestions: false});

  @override
  bool computeFast(DartCompletionRequest request) {
    OpType optype = request.optype;
    if (optype.includeTopLevelSuggestions) {
      builder = new _ImportedSuggestionBuilder(
          request,
          typesOnly: optype.includeOnlyTypeNameSuggestions,
          excludeVoidReturn: !optype.includeVoidReturnSuggestions);
      builder.shouldWaitForLowPrioritySuggestions =
          shouldWaitForLowPrioritySuggestions;
      return builder.computeFast(request.node);
    }
    return true;
  }

  @override
  Future<bool> computeFull(DartCompletionRequest request) {
    if (builder != null) {
      return builder.computeFull(request.node);
    }
    return new Future.value(false);
  }
}

/**
 * [_ImportedSuggestionBuilder] traverses the imports and builds suggestions
 * based upon imported elements.
 */
class _ImportedSuggestionBuilder extends ElementSuggestionBuilder implements
    SuggestionBuilder {
  bool shouldWaitForLowPrioritySuggestions;
  final DartCompletionRequest request;
  final bool typesOnly;
  final bool excludeVoidReturn;
  DartCompletionCache cache;

  _ImportedSuggestionBuilder(this.request, {this.typesOnly: false,
      this.excludeVoidReturn: false}) {
    cache = request.cache;
  }

  @override
  CompletionSuggestionKind get kind => CompletionSuggestionKind.INVOCATION;

  /**
   * If the needed information is cached, then add suggestions and return `true`
   * else return `false` indicating that additional work is necessary.
   */
  bool computeFast(AstNode node) {
    CompilationUnit unit = request.unit;
    if (cache.isImportInfoCached(unit)) {
      _addInheritedSuggestions(node);
      _addTopLevelSuggestions();
      return true;
    }
    return false;
  }

  /**
   * Compute suggested based upon imported elements.
   */
  Future<bool> computeFull(AstNode node) {

    Future<bool> addSuggestions(_) {
      _addInheritedSuggestions(node);
      _addTopLevelSuggestions();
      return new Future.value(true);
    }

    Future future = null;
    if (!cache.isImportInfoCached(request.unit)) {
      future = cache.computeImportInfo(
          request.unit,
          request.searchEngine,
          shouldWaitForLowPrioritySuggestions);
    }
    if (future != null) {
      return future.then(addSuggestions);
    }
    return addSuggestions(true);
  }

  /**
   * Add imported element suggestions.
   */
  void _addElementSuggestions(List<Element> elements) {
    elements.forEach((Element elem) {
      if (elem is! ClassElement) {
        if (typesOnly) {
          return;
        }
        if (elem is ExecutableElement) {
          DartType returnType = elem.returnType;
          if (returnType != null && returnType.isVoid) {
            if (excludeVoidReturn) {
              return;
            }
          }
        }
      }
      addSuggestion(elem);
    });
  }

  /**
   * Add suggestions for any inherited imported members.
   */
  void _addInheritedSuggestions(AstNode node) {
    var classDecl = node.getAncestor((p) => p is ClassDeclaration);
    if (classDecl is ClassDeclaration) {
      // Build a list of inherited types that are imported
      // and include any inherited imported members
      List<String> inheritedTypes = new List<String>();
      visitInheritedTypes(classDecl, (_) {
        // local declarations are handled by the local computer
      }, (String typeName) {
        inheritedTypes.add(typeName);
      });
      HashSet<String> visited = new HashSet<String>();
      while (inheritedTypes.length > 0) {
        String name = inheritedTypes.removeLast();
        ClassElement elem = cache.importedClassMap[name];
        if (visited.add(name) && elem != null) {
          _addElementSuggestions(elem.fields);
          _addElementSuggestions(elem.accessors);
          _addElementSuggestions(elem.methods);
          elem.allSupertypes.forEach((InterfaceType type) {
            if (visited.add(type.name) && type.element != null) {
              _addElementSuggestions(type.element.fields);
              _addElementSuggestions(type.element.accessors);
              _addElementSuggestions(type.element.methods);
            }
          });
        }
      }
    }
  }

  /**
   * Add top level suggestions from the cache.
   * To reduce the number of suggestions sent to the client,
   * filter the suggestions based upon the first character typed.
   * If no characters are available to use for filtering,
   * then exclude all low priority suggestions.
   */
  void _addTopLevelSuggestions() {
    String filterText = request.filterText;
    if (filterText.length > 1) {
      filterText = filterText.substring(0, 1);
    }

    //TODO (danrubel) Revisit this filtering once paged API has been added
    addFilteredSuggestions(List<CompletionSuggestion> unfiltered) {
      unfiltered.forEach((CompletionSuggestion suggestion) {
        if (filterText.length > 0) {
          if (suggestion.completion.startsWith(filterText)) {
            request.suggestions.add(suggestion);
          }
        } else {
          if (suggestion.relevance != COMPLETION_RELEVANCE_LOW) {
            request.suggestions.add(suggestion);
          }
        }
      });
    }

    DartCompletionCache cache = request.cache;
    addFilteredSuggestions(cache.importedTypeSuggestions);
    addFilteredSuggestions(cache.libraryPrefixSuggestions);
    if (!typesOnly) {
      addFilteredSuggestions(cache.otherImportedSuggestions);
      if (!excludeVoidReturn) {
        addFilteredSuggestions(cache.importedVoidReturnSuggestions);
      }
    }
  }
}
