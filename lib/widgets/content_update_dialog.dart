import 'package:flutter/material.dart';

import '../services/content_update_manager.dart';
import '../services/content_update_manifest.dart';

// Reuses update_dialog.dart's Oak-box palette for visual consistency.
const _boxBg = Color(0xFF083048);
const _boxBorder = Color(0xFFF8F0E0);
const _textColor = Color(0xFFF8F0E0);
const _accent = Color(0xFFC9A44C);

/// Blocking dialog shown when required content bundles must download before
/// the player can continue (spec: "Required Content Update"). Not
/// dismissible — no barrier tap, no back button, no "Later".
class ContentUpdateDialog extends StatefulWidget {
  const ContentUpdateDialog({super.key, required this.diffs, required this.baseUrl, this.changeNotes = const []});

  /// Required, changed bundles only.
  final List<BundleDiff> diffs;
  final String baseUrl;

  /// Bullet points describing what changed (spec §18), shown above the
  /// progress bar. Empty when the deploy didn't supply any.
  final List<String> changeNotes;

  @override
  State<ContentUpdateDialog> createState() => _ContentUpdateDialogState();
}

class _ContentUpdateDialogState extends State<ContentUpdateDialog> {
  int _currentIndex = 0;
  DownloadStage _stage = DownloadStage.downloading;
  int _received = 0;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final manager = ContentUpdateManager.instance;
    for (var i = 0; i < widget.diffs.length; i++) {
      if (!mounted) return;
      final diff = widget.diffs[i];
      setState(() {
        _currentIndex = i;
        _stage = DownloadStage.downloading;
        _received = 0;
        _total = diff.remote.sizeBytes;
        _error = null;
      });

      var failed = false;
      await for (final progress in manager.downloadAndActivate(diff, baseUrl: widget.baseUrl)) {
        if (!mounted) return;
        setState(() {
          _stage = progress.stage;
          _received = progress.bytesReceived;
          if (progress.totalBytes > 0) _total = progress.totalBytes;
          if (progress.stage == DownloadStage.failed) {
            _error = progress.error ?? 'Update verification failed.';
            failed = true;
          }
        });
      }
      if (failed) return; // Stay on screen with a Retry option.
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _retry() {
    setState(() => _error = null);
    _run();
  }

  String _stageLabel(DownloadStage stage) {
    switch (stage) {
      case DownloadStage.downloading:
        return 'Downloading…';
      case DownloadStage.verifying:
        return 'Verifying…';
      case DownloadStage.extracting:
        return 'Extracting…';
      case DownloadStage.activating:
        return 'Activating…';
      case DownloadStage.done:
        return 'Done';
      case DownloadStage.failed:
        return 'Failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final progressValue = _total > 0 ? _received / _total : null;
    final sizeLabel = _total > 0 ? '${(_total / 1024 / 1024).toStringAsFixed(1)} MB' : '';
    final multi = widget.diffs.length > 1 ? '(${_currentIndex + 1}/${widget.diffs.length}) ' : '';

    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.black87,
        child: SafeArea(
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                color: _boxBg,
                border: Border.all(color: _boxBorder, width: 2.5),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 6)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'GAME DATA UPDATE',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 13,
                      fontFamily: 'PowerGreen',
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _error != null
                        ? '$_error\nThe file may be incomplete or corrupted.'
                        : 'New game data is required to continue.\n$multi$sizeLabel',
                    style: const TextStyle(color: _textColor, fontSize: 13, fontFamily: 'PowerGreen', height: 1.5),
                  ),
                  if (_error == null && widget.changeNotes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Changes:',
                      style: TextStyle(color: _textColor.withValues(alpha: 0.85), fontSize: 12, fontFamily: 'PowerGreen', fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    ...widget.changeNotes.map(
                      (note) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '• $note',
                          style: TextStyle(color: _textColor.withValues(alpha: 0.75), fontSize: 12, fontFamily: 'PowerGreen', height: 1.4),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (_error == null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progressValue,
                        minHeight: 10,
                        color: _accent,
                        backgroundColor: _boxBg.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _stageLabel(_stage),
                      style: TextStyle(color: _textColor.withValues(alpha: 0.6), fontSize: 11, fontFamily: 'PowerGreen'),
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: _retry,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.2),
                          ),
                          child: const Text(
                            'RETRY',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontFamily: 'PowerGreen',
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the blocking required-update dialog if any required bundle in
/// [diffs] has changed. No-op otherwise.
Future<void> showContentUpdateDialogIfNeeded(
  BuildContext context, {
  required List<BundleDiff> diffs,
  required String baseUrl,
  List<String> changeNotes = const [],
}) async {
  final required = diffs.where((d) => d.isRequired && d.isChanged).toList();
  if (required.isEmpty) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ContentUpdateDialog(diffs: required, baseUrl: baseUrl, changeNotes: changeNotes),
  );
}
