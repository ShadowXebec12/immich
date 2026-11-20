import 'package:immich_mobile/domain/utils/event_stream.dart';

// Timeline Events
class TimelineReloadEvent extends Event {
  const TimelineReloadEvent();
}

class ScrollToTopEvent extends Event {
  const ScrollToTopEvent();
}

class ScrollToDateEvent extends Event {
  final DateTime date;

  const ScrollToDateEvent(this.date);
}

// Asset Viewer Events
class ViewerShowDetailsEvent extends Event {
  const ViewerShowDetailsEvent();
}

class ViewerReloadAssetEvent extends Event {
  const ViewerReloadAssetEvent();
}

// Custom fork: the viewer closed on [index] of [timeline]; the grid showing that timeline scrolls it into view
class ViewerClosedEvent extends Event {
  final Object timeline;
  final int index;

  const ViewerClosedEvent(this.timeline, this.index);
}

// Custom fork: go to the next photo (after favoriting or labeling one)
class ViewerAdvanceEvent extends Event {
  const ViewerAdvanceEvent();
}

class ViewerStackAssetDeletedEvent extends Event {
  final int stackIndex;

  const ViewerStackAssetDeletedEvent({required this.stackIndex});
}

// Multi-Select Events
class MultiSelectToggleEvent extends Event {
  final bool isEnabled;
  const MultiSelectToggleEvent(this.isEnabled);
}

// Map Events
class MapMarkerReloadEvent extends Event {
  const MapMarkerReloadEvent();
}
