import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'lead_pipeline_constants.dart';

/// Asks why a lead moved stage.
///
/// The backend records the transition either way; this is only about capturing
/// the reason. Until it existed a move said *what* happened and never *why*,
/// which is the thing the next person picking up the lead actually needs.
///
/// Three outcomes, and the difference matters:
///
///   - **Save** — move, with the note.
///   - **Skip** — move, no note. One tap, because dragging a card across a
///     board is meant to be fast and a prompt that cannot be dismissed quickly
///     gets answered with "." forever.
///   - **Dismiss** — do not move at all. Returns null, so a mis-drag is
///     undoable by swiping the sheet away rather than dragging the card back.
///
/// Marking a lead lost keeps its own dialog: that reason is required, and this
/// one is not.
Future<StageNote?> showStageNoteSheet(
  BuildContext context, {
  required String leadName,
  required String fromStatus,
  required String toStatus,
}) {
  return showModalBottomSheet<StageNote>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StageNoteSheet(
      leadName: leadName,
      fromStatus: fromStatus,
      toStatus: toStatus,
    ),
  );
}

class StageNote {
  final String note;
  const StageNote(this.note);
}

class _StageNoteSheet extends StatefulWidget {
  final String leadName;
  final String fromStatus;
  final String toStatus;

  const _StageNoteSheet({
    required this.leadName,
    required this.fromStatus,
    required this.toStatus,
  });

  @override
  State<_StageNoteSheet> createState() => _StageNoteSheetState();
}

class _StageNoteSheetState extends State<_StageNoteSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final from = stageFor(widget.fromStatus);
    final to = stageFor(widget.toStatus);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text(widget.leadName,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),

                // The transition, spelled out. On a board the drag already
                // showed it; from a list or a detail screen it did not.
                Row(
                  children: [
                    _chip(from.label, Colors.grey.shade600),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 15, color: Colors.grey.shade500),
                    ),
                    _chip(to.label, AppColors.primary),
                  ],
                ),

                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  maxLines: 2,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    labelText: 'Why? (optional)',
                    hintText: 'e.g. booked Saturday 7am with Simran',
                    hintStyle: TextStyle(
                        fontSize: 12.5, color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                  onSubmitted: (_) =>
                      Navigator.pop(context, StageNote(_controller.text)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Goes on the lead’s timeline next to the move.',
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),

                const SizedBox(height: 16),

                // Stacked rather than a Skip/Move row. The row put the primary
                // action hard against the right edge of a sheet that already
                // sits at the bottom of the screen, and on a short viewport it
                // did not paint at all. Full width is a bigger target, works at
                // any height, and reads in the order the decision is made.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.pop(context, StageNote(_controller.text)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Move'),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  // Skip moves the lead without a note. Dismissing the sheet
                  // does not move it at all — different intentions, so they
                  // never share a control.
                  child: TextButton(
                    onPressed: () =>
                        Navigator.pop(context, const StageNote('')),
                    child: Text('Move without a note',
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.grey.shade700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: colour)),
      );
}
