import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/scanner.dart';

/**
 * A CompletionTarget represents an edge in the parse tree which connects an
 * AST node (the [containingNode] of the completion) to one of its children
 * (the [entity], which represents the place in the parse tree where the newly
 * completed text will be inserted).
 *
 * To illustrate, consider the following snippet of code, and its associated
 * parse tree.  (T's represent tokens, N's represent AST nodes.  Some trivial
 * AST nodes are not shown).
 *
 *            ___N        (function declaration)
 *           /    \
 *          /    __N_______  (function body)
 *         /    /  |a      \
 *        /    /   N______  \  (statement)
 *       /    /   /       \  \
 *      /    /   N____     \  \  (assignment expression)
 *     |    /   /|    \     \  \
 *     .   |   / |    _N___  \  |  ("as" expression)
 *     .   |  |  |   / |   \c | |
 *     .   |  N  |  N  |b   N | |  (simple identifiers)
 *         |  |  |  |  |    | | |
 *         T  T  T  T  T    T T T
 *     m() { foo = bar as  Baz; }
 *
 * The Completion target is usually placed as high in the tree as possible so
 * that we can produce the most meaningful completions with minimal effort.
 * For instance, if the cursor is inside the identifier "foo", the completion
 * target will be the edge marked "a", so that we will produce all completions
 * that could possibly start a statement, even those which would conflict with
 * the current parse (such as the keyword "for", which begins a "for"
 * statement).  As a consequence of this, the [entity] will usually not be the
 * first child of the [containingNode] node.
 *
 * Note that the [containingNode] is always an AST node, but the [entity] may
 * not be.  For instance, if the cursor is inside the keyword "as", the
 * completion target will be the edge marked "b", so the [entity] is the token
 * "as".
 *
 * If the cursor is between tokens, the completion target is usually associated
 * with the token that follows the cursor (since that's the token that will be
 * displaced when the new text is inserted).  For example, if the cursor is
 * after the "{" character, then the completion target will be the edge marked
 * "a", just as it is if the cursor is inside the identifier "foo".  However
 * there is one exception: if the cursor is at the rightmost edge of a keyword
 * or identifier, then the completion target is associated with that token,
 * since any further letters typed will change the meaning of the identifier or
 * keyword, rather than creating a new token.  So for instance, if the cursor
 * is just after the "s" of "as", the completion target will be the edge marked
 * "b", but if the cursor target is after the first space following "as", then
 * the completion target will be the edge marked "c".
 *
 * If the file is empty, or the cursor is after all the text in the file, then
 * there may be no edge in the parse tree which is appropriate to act as the
 * completion target; in this case, [entity] is set to null and
 * [containingNode] is set to the CompilationUnit.
 */
class CompletionTarget {
  /**
   * The context in which the completion is occurring.  This is the AST node
   * which is a direct parent of [entity].
   */
  final AstNode containingNode;

  /**
   * The entity which the completed text will replace (or which will be
   * displaced once the completed text is inserted).  This may be an AstNode or
   * a Token, or it may be null if the cursor is after all tokens in the file.
   *
   * Usually, the entity won't be the first child of the [containingNode] (this
   * is a consequence of placing the completion target as high in the tree as
   * possible).  However, there is one exception: when the cursor is inside of
   * a multi-character token which is not a keyword or identifier (e.g. a
   * comment, or a token like "+=", the entity will be always be the token.
   */
  final Object entity;

  /**
   * Compute the appropriate [CompletionTarget] for the given [offset] within
   * the [compilationUnit].
   */
  factory CompletionTarget.forOffset(CompilationUnit compilationUnit,
      int offset) {
    // The precise algorithm is as follows.  We perform a depth-first search of
    // all edges in the parse tree (both those that point to AST nodes and
    // those that point to tokens), visiting parents before children.  The
    // first edge which points to an entity satisfying either _isCandidateToken
    // or _isCandidateNode is the completion target.  If no edge is found that
    // satisfies these two predicates, then we set the completion target entity
    // to null and the containingNode to the compilationUnit.
    //
    // Note that if a token is not a candidate target, then none of the tokens
    // that precede it are candidate targets either.  Therefore any entity
    // whose last token is not a candidate target can be skipped.  This lets us
    // prune the search to the point where no recursion is necessary; at each
    // step in the process we know exactly which child node we need to proceed
    // to.
    AstNode containingNode = compilationUnit;
    outerLoop: while (true) {
      if (containingNode is Comment) {
        // Comments are handled specially: we descend into any CommentReference
        // child node that contains the cursor offset.
        Comment comment = containingNode;
        for (CommentReference commentReference in comment.references) {
          if (commentReference.offset <= offset &&
              offset <= commentReference.end) {
            containingNode = commentReference;
            continue outerLoop;
          }
        }
      }
      for (var entity in containingNode.childEntities) {
        if (entity is Token) {
          if (_isCandidateToken(entity, offset)) {
            // Target found.
            return new CompletionTarget._(containingNode, entity);
          } else {
            // Since entity is a token, we don't need to look inside it; just
            // proceed to the next entity.
            continue;
          }
        } else if (entity is AstNode) {
          // If the last token in the node isn't a candidate target, then
          // neither the node nor any of its descendants can possibly be the
          // completion target, so we can skip the node entirely.
          if (!_isCandidateToken(entity.endToken, offset)) {
            continue;
          }

          // If the node is a candidate target, then we are done.
          if (_isCandidateNode(entity, offset)) {
            return new CompletionTarget._(containingNode, entity);
          }

          // Otherwise, the completion target is somewhere inside the entity,
          // so we need to jump to the start of the outer loop to examine its
          // contents.
          containingNode = entity;
          continue outerLoop;
        } else {
          // Unexpected entity found (all entities in a parse tree should be
          // AST nodes or tokens).
          assert(false);
        }
      }

      // No completion target found.  It should only be possible to reach here
      // the first time through the outer loop (since we only jump to the start
      // of the outer loop after determining that the completion target is
      // inside an entity).  We can check that assumption by verifying that
      // containingNode is still the compilationUnit.
      assert(identical(containingNode, compilationUnit));

      // Since no completion target was found, we set the completion target
      // entity to null and use the compilationUnit as the parent.
      return new CompletionTarget._(compilationUnit, null);
    }
  }

  /**
   * Create a [CompletionTarget] holding the given [containingNode] and
   * [entity].
   */
  CompletionTarget._(this.containingNode, this.entity);

  /**
   * Determine whether [node] could possibly be the [entity] for a
   * [CompletionTarget] associated with the given [offset].
   */
  static bool _isCandidateNode(AstNode node, int offset) {
    // If the node's first token is a keyword or identifier, then the node is a
    // candidate entity if its first token is.
    Token beginToken = node.beginToken;
    if (beginToken.type == TokenType.KEYWORD ||
        beginToken.type == TokenType.IDENTIFIER) {
      return _isCandidateToken(beginToken, offset);
    }

    // Otherwise, the node is a candidate entity only if the offset is before
    // the beginning of the node.  This ensures that completions within a token
    // (e.g. inside a literal string or inside a comment) are evaluated within
    // the context of the token itself.
    return offset <= node.offset;
  }

  /**
   * Determine whether [token] could possibly be the [entity] for a
   * [CompletionTarget] associated with the given [offset].
   */
  static bool _isCandidateToken(Token token, int offset) {
    // A token is considered a candidate entity if the cursor offset is (a)
    // before the start of the token, (b) within the token, (c) at the end of
    // the token and the token is a keyword or identifier, or (d) at the
    // location of the token and the token is zero length.
    if (offset < token.end) {
      return true;
    } else if (offset == token.end) {
      return token.type == TokenType.KEYWORD ||
          token.type == TokenType.IDENTIFIER ||
          token.length == 0;
    } else {
      return false;
    }
  }
}
