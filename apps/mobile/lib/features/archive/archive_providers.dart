import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../board/board_controller.dart';

/// Which bin a listing shows. Archive is indefinite; Trash purges after 30 days.
enum ArchiveMode {
  archive('Archive'),
  trash('Trash');

  const ArchiveMode(this.label);
  final String label;
}

/// Family key for [archiveListingProvider]; `boardId == null` means account-wide.
typedef ArchiveQuery = ({ArchiveMode mode, String? boardId});

/// Account-wide (or one board's) archived / trashed boards and items.
///
/// Tests override this directly with fixture listings so no HTTP is needed.
final archiveListingProvider = FutureProvider.autoDispose.family<ArchiveListing, ArchiveQuery>((ref, query) {
  final repo = ref.read(boardRepositoryProvider);
  return switch (query.mode) {
    ArchiveMode.archive => repo.archive(boardId: query.boardId),
    ArchiveMode.trash => repo.trash(boardId: query.boardId),
  };
});
