/*
 * Copyright (c) 2013, the Dart project authors.
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

package com.google.dart.engine.services.internal.refactoring;

import com.google.common.base.Objects;
import com.google.dart.engine.element.ClassElement;
import com.google.dart.engine.element.CompilationUnitElement;
import com.google.dart.engine.element.Element;
import com.google.dart.engine.element.ElementKind;
import com.google.dart.engine.element.ImportElement;
import com.google.dart.engine.element.LibraryElement;
import com.google.dart.engine.element.visitor.GeneralizingElementVisitor;
import com.google.dart.engine.search.SearchEngine;
import com.google.dart.engine.search.SearchMatch;
import com.google.dart.engine.services.internal.correction.CorrectionUtils;
import com.google.dart.engine.services.refactoring.ProgressMonitor;
import com.google.dart.engine.services.status.RefactoringStatus;
import com.google.dart.engine.services.status.RefactoringStatusContext;

import static com.google.dart.engine.services.internal.correction.CorrectionUtils.getElementKindName;
import static com.google.dart.engine.services.internal.correction.CorrectionUtils.getElementQualifiedName;
import static com.google.dart.engine.services.internal.correction.CorrectionUtils.hasDisplayName;

import java.text.MessageFormat;
import java.util.List;

/**
 * Helper to check if renaming or creating {@link Element} with given name will cause any problems.
 */
class RenameUnitMemberValidator {
  private final SearchEngine searchEngine;
  private final Element element;
  private final ElementKind elementKind;
  private final String newName;

  public RenameUnitMemberValidator(SearchEngine searchEngine, Element element,
      ElementKind elementKind, String newName) {
    this.searchEngine = searchEngine;
    this.element = element;
    this.elementKind = elementKind;
    this.newName = newName;
  }

  public RefactoringStatus validate(ProgressMonitor pm, boolean isRename) {
    pm.beginTask("Analyze possible conflicts", 3);
    try {
      final RefactoringStatus result = new RefactoringStatus();
      // check if there are top-level declarations with "newName" in the same LibraryElement
      {
        LibraryElement library = element.getAncestor(LibraryElement.class);
        library.accept(new GeneralizingElementVisitor<Void>() {
          @Override
          public Void visitElement(Element element) {
            // library or unit
            if (element instanceof LibraryElement || element instanceof CompilationUnitElement) {
              return super.visitElement(element);
            }
            // top-level
            if (hasDisplayName(element, newName)) {
              String message = MessageFormat.format(
                  "Library already declares {0} with name ''{1}''.",
                  getElementKindName(element),
                  newName);
              result.addError(message, new RefactoringStatusContext(element));
            }
            return null;
          }
        });
        pm.worked(1);
      }
      // may be shadowed by class member
      if (isRename) {
        List<SearchMatch> references = searchEngine.searchReferences(element, null, null);
        for (SearchMatch reference : references) {
          ClassElement refEnclosingClass = reference.getElement().getAncestor(ClassElement.class);
          if (refEnclosingClass != null) {
            refEnclosingClass.accept(new GeneralizingElementVisitor<Void>() {
              @Override
              public Void visitElement(Element maybeShadow) {
                // class
                if (maybeShadow instanceof ClassElement) {
                  return super.visitElement(maybeShadow);
                }
                // class member
                if (hasDisplayName(maybeShadow, newName)) {
                  String message = MessageFormat.format(
                      "Reference to renamed {0} will shadowed by {1} ''{2}''.",
                      getElementKindName(elementKind),
                      getElementKindName(maybeShadow),
                      getElementQualifiedName(maybeShadow));
                  result.addError(message, new RefactoringStatusContext(maybeShadow));
                }
                return null;
              }
            });
          }
        }
        pm.worked(1);
      }
      // may be shadows inherited class members
      {
        List<SearchMatch> nameDeclarations = searchEngine.searchDeclarations(newName, null, null);
        for (SearchMatch nameDeclaration : nameDeclarations) {
          Element member = nameDeclaration.getElement();
          Element declarationClass = member.getEnclosingElement();
          if (declarationClass instanceof ClassElement) {
            List<SearchMatch> memberReferences = searchEngine.searchReferences(member, null, null);
            for (SearchMatch memberReference : memberReferences) {
              if (!memberReference.isQualified()) {
                Element referenceElement = memberReference.getElement();
                ClassElement referenceClass = referenceElement.getAncestor(ClassElement.class);
                if (!Objects.equal(referenceClass, declarationClass)) {
                  if (!isVisibleAt(element, memberReference)) {
                    continue;
                  }
                  String message = MessageFormat.format(
                      isRename ? "Renamed {0} will shadow {1} ''{2}''."
                          : "Created {0} will shadow {1} ''{2}''.",
                      getElementKindName(elementKind),
                      getElementKindName(member),
                      getElementQualifiedName(member));
                  result.addError(message, RefactoringStatusContext.create(memberReference));
                }
              }
            }
          }
        }
        pm.worked(1);
      }
      // done
      return result;
    } finally {
      pm.done();
    }
  }

  /**
   * @return {@code true} if the given {@link Element} is visible at the given {@link SearchMatch}.
   */
  private boolean isVisibleAt(Element element, SearchMatch at) {
    LibraryElement library = at.getElement().getLibrary();
    // may be the same library
    if (element.getLibrary().equals(library)) {
      return true;
    }
    // check imports
    for (ImportElement importElement : library.getImports()) {
      // ignore if imported with prefix
      if (importElement.getPrefix() != null) {
        continue;
      }
      // check imported elements
      if (CorrectionUtils.getImportNamespace(importElement).containsValue(element)) {
        return true;
      }
    }
    // no, it is not visible
    return false;
  }
}
