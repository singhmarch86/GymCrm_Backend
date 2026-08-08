// Data-import models. See docs/FR-05-data-import.md in the backend repo.
//
// Import is deliberately two-phase: a batch is validated (nothing written)
// before it is committed. These models carry the preview that sits between
// those two steps.

class ImportRowResult {
  final int lineNumber;
  final String status; // valid | invalid | duplicate | imported | skipped | updated
  final String? errorMessage;
  final Map<String, String> data;

  ImportRowResult({
    required this.lineNumber,
    required this.status,
    this.errorMessage,
    required this.data,
  });

  bool get isProblem => status == 'invalid' || status == 'duplicate';

  /// A short label for the row, assembled from whichever identifying columns
  /// the file happened to carry.
  String get label {
    final name = [data['first_name'] ?? '', data['last_name'] ?? ''].join(' ').trim();
    if (name.isNotEmpty) return name;
    return data['phone'] ?? data['plan'] ?? 'Row $lineNumber';
  }

  factory ImportRowResult.fromJson(Map<String, dynamic> j) => ImportRowResult(
        lineNumber: j['line_number'] ?? 0,
        status: j['status'] ?? 'valid',
        errorMessage: j['error_message'],
        data: ((j['data'] as Map?) ?? {})
            .map((k, v) => MapEntry(k.toString(), (v ?? '').toString())),
      );
}

class ImportBatch {
  final int id;
  final String entityType;
  final String? filename;
  final String status; // validated | committed | discarded
  final String duplicatePolicy;

  final int totalRows;
  final int validRows;
  final int invalidRows;
  final int duplicateRows;
  final int importedRows;
  final int skippedRows;
  final int updatedRows;

  final String? committedAt;
  final String createdAt;
  final List<ImportRowResult> rows;

  ImportBatch({
    required this.id,
    required this.entityType,
    this.filename,
    required this.status,
    required this.duplicatePolicy,
    required this.totalRows,
    required this.validRows,
    required this.invalidRows,
    required this.duplicateRows,
    required this.importedRows,
    required this.skippedRows,
    required this.updatedRows,
    this.committedAt,
    required this.createdAt,
    this.rows = const [],
  });

  bool get isCommitted => status == 'committed';
  bool get canCommit => status == 'validated' && (validRows > 0 || duplicateRows > 0);

  /// Rows worth showing first — valid rows need no explanation, broken ones do.
  List<ImportRowResult> get problems => rows.where((r) => r.isProblem).toList();

  factory ImportBatch.fromJson(Map<String, dynamic> j) => ImportBatch(
        id: j['id'] ?? 0,
        entityType: j['entity_type'] ?? 'members',
        filename: j['filename'],
        status: j['status'] ?? 'validated',
        duplicatePolicy: j['duplicate_policy'] ?? 'skip',
        totalRows: j['total_rows'] ?? 0,
        validRows: j['valid_rows'] ?? 0,
        invalidRows: j['invalid_rows'] ?? 0,
        duplicateRows: j['duplicate_rows'] ?? 0,
        importedRows: j['imported_rows'] ?? 0,
        skippedRows: j['skipped_rows'] ?? 0,
        updatedRows: j['updated_rows'] ?? 0,
        committedAt: j['committed_at'],
        createdAt: j['created_at'] ?? '',
        rows: ((j['rows'] as List?) ?? [])
            .map((e) => ImportRowResult.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
