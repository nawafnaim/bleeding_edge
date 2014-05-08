// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library trydart.htmlToText;

import 'dart:math' show
    max;

import 'dart:html' show
    Element,
    Node,
    NodeFilter,
    ShadowRoot,
    Text,
    TreeWalker;

import 'selection.dart' show
    TrySelection;

/// Returns true if [node] is a block element, that is, not inline.
bool isBlockElement(Node node) {
  if (node is! Element) return false;
  Element element = node;

  // TODO(ahe): Remove this line by changing code completion to avoid using a
  // div element.
  if (element.classes.contains('dart-code-completion')) return false;

  return element.getComputedStyle().display != 'inline';
}

/// Position [walker] at the last predecessor (that is, child of child of
/// child...) of [node]. The next call to walker.nextNode will return the first
/// node after [node].
void skip(Node node, TreeWalker walker) {
  if (walker.nextSibling() != null) {
    walker.previousNode();
    return;
  }
  for (Node current = walker.nextNode();
       current != null;
       current = walker.nextNode()) {
    if (!node.contains(current)) {
      walker.previousNode();
      return;
    }
  }
}

/// Writes the text of [root] to [buffer]. Keeps track of [selection] and
/// returns the new anchorOffset from beginning of [buffer] or -1 if the
/// selection isn't in [root].
int htmlToText(Node root,
               StringBuffer buffer,
               TrySelection selection,
               {bool treatRootAsInline: false}) {
  int selectionOffset = -1;
  TreeWalker walker = new TreeWalker(root, NodeFilter.SHOW_ALL);

  for (Node node = root; node != null; node = walker.nextNode()) {
    switch (node.nodeType) {
      case Node.CDATA_SECTION_NODE:
      case Node.TEXT_NODE:
        if (selection.anchorNode == node) {
          selectionOffset = selection.anchorOffset + buffer.length;
        }
        Text text = node;
        buffer.write(text.data.replaceAll('\xA0', ' '));
        break;

      default:
        if (!ShadowRoot.supported &&
            node is Element &&
            node.getAttribute('try-dart-shadow-root') != null) {
          skip(node, walker);
        } else if (node.nodeName == 'BR') {
          buffer.write('\n');
        } else if (node != root && isBlockElement(node)) {
          selectionOffset =
              max(selectionOffset, htmlToText(node, buffer, selection));
          skip(node, walker);
        }
        break;
    }
  }

  if (!treatRootAsInline && isBlockElement(root)) {
    buffer.write('\n');
  }

  return selectionOffset;
}
