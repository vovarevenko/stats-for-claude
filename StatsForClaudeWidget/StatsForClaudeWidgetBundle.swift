import WidgetKit
import SwiftUI

@main
struct StatsForClaudeWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatsForClaudeWidget()
    }
}

// Placeholder — full implementation in step 8
struct StatsForClaudeWidget: Widget {
    let kind = "StatsForClaudeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlaceholderProvider()) { entry in
            Text(entry.date, style: .time)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Stats for Claude")
        .description("Claude Code usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { PlaceholderEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .atEnd))
    }
}
