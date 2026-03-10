import 'package:flutter/material.dart';
import 'package:flutter_story_presenter/flutter_story_presenter.dart';
import 'package:visibility_detector/visibility_detector.dart';

typedef OnTextStoryLoaded = void Function(bool isLoaded, bool isVisible, bool isInitial);

class TextStoryView extends StatefulWidget {
  const TextStoryView({
    super.key,
    required this.storyItem,
    this.onVisibilityChanged,
  });

  final StoryItem storyItem;
  final OnTextStoryLoaded? onVisibilityChanged;

  @override
  State<TextStoryView> createState() => _TextStoryViewState();
}

class _TextStoryViewState extends State<TextStoryView> {
  bool _hasNotifiedInitialVisibility = false;

  void _notifyVisibilityChanged({required bool isLoaded, required bool isVisible}) {
    final isInitial = !_hasNotifiedInitialVisibility;
    _hasNotifiedInitialVisibility = true;
    widget.onVisibilityChanged?.call(isLoaded, isVisible, isInitial);
  }

  @override
  void initState() {
    super.initState();
    _notifyVisibilityChanged(isLoaded: true, isVisible: false);
  }

  @override
  Widget build(BuildContext context) {
    final storyItem = widget.storyItem;

    return VisibilityDetector(
      key: ValueKey(widget.storyItem.url ?? widget.storyItem.hashCode.toString()),
      onVisibilityChanged: (info) {
        if (info.visibleFraction == 0) {
          _notifyVisibilityChanged(isLoaded: true, isVisible: false);
        } else if (info.visibleFraction == 1) {
          _notifyVisibilityChanged(isLoaded: true, isVisible: true);
        }
      },
      child: Container(
        color: storyItem.textConfig?.backgroundColor,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (storyItem.textConfig?.backgroundWidget != null) ...{
              storyItem.textConfig!.backgroundWidget!,
            },
            if (storyItem.textConfig?.textWidget != null) ...{
              storyItem.textConfig!.textWidget!,
            } else ...{
              Align(
                alignment: widget.storyItem.textConfig?.textAlignment ??
                    Alignment.center,
                child: Text(
                  widget.storyItem.url!,
                ),
              ),
            }
          ],
        ),
      ),
    );
  }
}
