import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_misc.dart';

/// Debounced search over boards and items.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  SearchResults? _results;
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _results = null;
        _error = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(query));
  }

  Future<void> _run(String query) async {
    try {
      final json = await ApiClient.instance.get('/search', query: {'q': query});
      if (!mounted || _query.text.trim() != query) return;
      setState(() {
        _results = SearchResults.fromJson(json);
        _error = null;
        _searching = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final results = _results;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: 'Search boards and items',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Clear',
                    onPressed: () {
                      _query.clear();
                      _onChanged('');
                    },
                  ),
          ),
        ),
      ),
      body: Builder(builder: (context) {
        if (_error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(DfSpacing.xl),
              child: Text(_error!, textAlign: TextAlign.center, style: text.bodySmall),
            ),
          );
        }
        if (_query.text.trim().length < 2) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(DfSpacing.xl),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.search_rounded, size: 32, color: DfColors.textTertiary),
                const SizedBox(height: DfSpacing.xs),
                Text('Type at least two characters', style: text.bodySmall),
              ]),
            ),
          );
        }
        if (_searching && results == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (results == null || results.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(DfSpacing.xl),
              child: Text('No matches for "${_query.text.trim()}"', style: text.bodySmall),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(DfSpacing.md),
          children: [
            if (results.boards.isNotEmpty) ...[
              Text('Boards', style: text.labelMedium),
              const SizedBox(height: DfSpacing.xs),
              for (final board in results.boards)
                Padding(
                  padding: const EdgeInsets.only(bottom: DfSpacing.xs),
                  child: DfCard(
                    padding: const EdgeInsets.all(DfSpacing.sm),
                    onTap: () => context.push('/boards/${board.id}'),
                    child: Row(children: [
                      const DfBoardGlyph(size: 32),
                      const SizedBox(width: DfSpacing.sm),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(board.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                          if (board.workspaceName.isNotEmpty)
                            Text(board.workspaceName, style: text.labelSmall),
                        ]),
                      ),
                    ]),
                  ),
                ),
              const SizedBox(height: DfSpacing.md),
            ],
            if (results.items.isNotEmpty) ...[
              Text('Items', style: text.labelMedium),
              const SizedBox(height: DfSpacing.xs),
              for (final item in results.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: DfSpacing.xs),
                  child: DfCard(
                    padding: const EdgeInsets.all(DfSpacing.sm),
                    onTap: () => context.push('/items/${item.id}'),
                    child: Row(children: [
                      Container(
                        width: 3,
                        height: 32,
                        margin: const EdgeInsets.only(right: DfSpacing.xs),
                        decoration: BoxDecoration(
                          color: DfColors.token(item.groupColor),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                          Text('${item.boardName} · ${item.groupTitle}', style: text.labelSmall),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ],
          ],
        );
      }),
    );
  }
}
