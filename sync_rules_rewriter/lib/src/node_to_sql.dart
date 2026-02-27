import 'package:sqlparser/sqlparser.dart';
import 'package:sqlparser/utils/node_to_text.dart';

final _syntheticReferenceQuoteHints =
    Expando<SyntheticReferenceQuoteHint>('syntheticReferenceQuoteHints');
final _syntheticStarQualifierEscapes =
    Expando<bool>('syntheticStarQualifierEscapes');

final class SyntheticReferenceQuoteHint {
  final bool entityEscaped;
  final bool columnEscaped;

  const SyntheticReferenceQuoteHint({
    required this.entityEscaped,
    required this.columnEscaped,
  });
}

void setSyntheticReferenceQuoteHint(
  Reference reference,
  SyntheticReferenceQuoteHint hint,
) {
  _syntheticReferenceQuoteHints[reference] = hint;
}

SyntheticReferenceQuoteHint? syntheticReferenceQuoteHint(Reference reference) {
  return _syntheticReferenceQuoteHints[reference];
}

void setSyntheticStarQualifierEscaped(StarResultColumn star, bool escaped) {
  _syntheticStarQualifierEscapes[star] = escaped;
}

bool? syntheticStarQualifierEscaped(StarResultColumn star) {
  return _syntheticStarQualifierEscapes[star];
}

final class _IdentifierPart {
  final String name;
  final IdentifierToken? token;
  final bool? escapedOverride;

  const _IdentifierPart(
    this.name, {
    this.token,
    this.escapedOverride,
  });
}

/// Variant of [NodeSqlBuilder] that preserves explicit double-quote escaping on
/// supported identifiers.
final class FixedNodeToSql extends NodeSqlBuilder {
  @override
  void visitTableReference(TableReference e, void arg) {
    final identifierTokens = _collectIdentifierTokens(e);
    final expectedTableParts = (e.schemaName != null ? 1 : 0) + 1;
    final schemaToken = e.schemaName != null &&
            identifierTokens.length >= expectedTableParts
        ? identifierTokens.first
        : null;
    final tableToken = _asIdentifierToken(e.tableNameToken) ??
        (identifierTokens.length >= expectedTableParts
            ? identifierTokens[e.schemaName != null ? 1 : 0]
            : null);
    final aliasToken = e.as != null && identifierTokens.length > expectedTableParts
        ? identifierTokens.last
        : null;

    _emitQualifiedIdentifierParts([
      if (e.schemaName != null)
        _IdentifierPart(e.schemaName!, token: schemaToken),
      _IdentifierPart(e.tableName, token: tableToken),
    ]);

    if (e.as != null) {
      keyword(TokenType.as);
      _emitIdentifierWithToken(e.as!, aliasToken);
    }
  }

  @override
  void visitReference(Reference e, void arg) {
    // Collect IdentifierTokens from the token chain to detect explicit quoting.
    final identifierTokens = _collectIdentifierTokens(e);
    final expectedParts =
        (e.schemaName != null ? 1 : 0) + (e.entityName != null ? 1 : 0) + 1;

    // If token count doesn't contain all reference parts, fall back to base behavior.
    if (identifierTokens.length < expectedParts) {
      final hint = syntheticReferenceQuoteHint(e);
      if (hint != null) {
        _emitQualifiedIdentifierParts([
          if (e.schemaName != null) _IdentifierPart(e.schemaName!),
          if (e.entityName != null)
            _IdentifierPart(
              e.entityName!,
              escapedOverride: hint.entityEscaped,
            ),
          _IdentifierPart(
            e.columnName,
            escapedOverride: hint.columnEscaped,
          ),
        ]);
        return;
      }

      super.visitReference(e, arg);
      return;
    }

    var tokenIndex = 0;
    _emitQualifiedIdentifierParts([
      if (e.schemaName != null)
        _IdentifierPart(e.schemaName!, token: identifierTokens[tokenIndex++]),
      if (e.entityName != null)
        _IdentifierPart(e.entityName!, token: identifierTokens[tokenIndex++]),
      _IdentifierPart(e.columnName, token: identifierTokens[tokenIndex]),
    ]);
  }

  /// Emits an identifier, preserving explicit quoting from the original token.
  void _emitIdentifierWithToken(String name, IdentifierToken? token,
      {bool? escapedOverride, bool spaceBefore = true, bool spaceAfter = true}) {
    final escaped = escapedOverride ?? token?.escaped ?? false;
    if (escaped) {
      symbol(escapeIdentifier(name),
          spaceBefore: spaceBefore, spaceAfter: spaceAfter);
    } else {
      identifier(name, spaceBefore: spaceBefore, spaceAfter: spaceAfter);
    }
  }

  void _emitQualifiedIdentifierParts(List<_IdentifierPart> parts) {
    for (final (i, part) in parts.indexed) {
      _emitIdentifierWithToken(
        part.name,
        part.token,
        escapedOverride: part.escapedOverride,
        spaceBefore: i == 0,
        spaceAfter: i == parts.length - 1,
      );
      if (i < parts.length - 1) {
        symbol('.');
      }
    }
  }

  static IdentifierToken? _asIdentifierToken(Token? token) {
    return token is IdentifierToken ? token : null;
  }

  /// Walks the token chain of an AST node and collects all [IdentifierToken]s.
  static List<IdentifierToken> _collectIdentifierTokens(AstNode node) {
    final tokens = <IdentifierToken>[];
    var token = node.first;
    while (token != null) {
      if (token is IdentifierToken) tokens.add(token);
      if (identical(token, node.last)) break;
      token = token.next;
    }
    return tokens;
  }

  @override
  void visitExpressionResultColumn(ExpressionResultColumn e, void arg) {
    visit(e.expression, arg);
    visitNullable(e.mappedBy, arg);

    if (e.as != null) {
      keyword(TokenType.as);
      final aliasToken = _findTrailingIdentifierToken(
        node: e,
        untilExclusive: e.expression.last,
      );
      _emitIdentifierWithToken(e.as!, aliasToken);
    }
  }

  @override
  void visitStarResultColumn(StarResultColumn e, void arg) {
    if (e.tableName == null) {
      super.visitStarResultColumn(e, arg);
      return;
    }

    final identifierTokens = _collectIdentifierTokens(e);
    final tableToken = identifierTokens.isNotEmpty ? identifierTokens.first : null;
    _emitIdentifierWithToken(
      e.tableName!,
      tableToken,
      escapedOverride: tableToken == null ? syntheticStarQualifierEscaped(e) : null,
    );
    symbol('.');
    symbol('*', spaceAfter: true);
  }

  static IdentifierToken? _findTrailingIdentifierToken({
    required AstNode node,
    Token? untilExclusive,
  }) {
    var token = node.last;
    while (token != null && !identical(token, untilExclusive)) {
      if (token case IdentifierToken()) {
        return token;
      }
      token = token.previous;
    }
    return null;
  }

  static String toSql(AstNode node) {
    final builder = FixedNodeToSql();
    builder.visit(node, null);
    return builder.buffer.toString();
  }
}
