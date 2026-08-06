import 'package:flutter/material.dart';

import '../services/content_update_manager.dart';
import '../services/content_update_manifest.dart';

const _accent = Color(0xFFC9A44C);

/// Non-blocking heads-up for optional bundle downloads (art, cosmetics,
/// etc.). Downloads start immediately in the background regardless of
/// whether the player dismisses this — it's informational, not a gate.
class OptionalContentSheet extends StatefulWidget {
  const OptionalContentSheet({super.key, required this.diffs, required this.baseUrl});

  /// Optional, changed bundles only.
  final List<BundleDiff> diffs;
  final String baseUrl;

  @override
  State<OptionalContentSheet> createState() => _OptionalContentSheetState();
}

class _OptionalContentSheetState extends State<OptionalContentSheet> {
  final Map<String, DownloadStage> _stages = {};

  @override
  void initState() {
    super.initState();
    _downloadAll();
  }

  Future<void> _downloadAll() async {
    final manager = ContentUpdateManager.instance;
    for (final diff in widget.diffs) {
      await for (final progress in manager.downloadAndActivate(diff, baseUrl: widget.baseUrl)) {
        if (!mounted) return;
        setState(() => _stages[diff.remote.id] = progress.stage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalBytes = widget.diffs.fold<int>(0, (sum, d) => sum + d.remote.sizeBytes);
    final sizeLabel = '${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB';
    final doneCount = _stages.values.where((s) => s == DownloadStage.done).length;
    final allDone = doneCount == widget.diffs.length;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Icon(
              allDone ? Icons.check_circle_outline : Icons.cloud_download_outlined,
              color: allDone ? Colors.green : _accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Optional Content',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    allDone ? 'Downloaded' : 'Downloading in background… $sizeLabel ($doneCount/${widget.diffs.length})',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Dismiss', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the optional-content banner if any optional bundle in [diffs] has
/// changed. No-op otherwise.
void showOptionalContentSheetIfNeeded(
  BuildContext context, {
  required List<BundleDiff> diffs,
  required String baseUrl,
}) {
  final optional = diffs.where((d) => !d.isRequired && d.isChanged).toList();
  if (optional.isEmpty) return;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => OptionalContentSheet(diffs: optional, baseUrl: baseUrl),
  );
}
