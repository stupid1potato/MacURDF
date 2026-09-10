import SwiftUI
import URDFCore

struct IssuesPanelPlaceholder: View {
    let issues: [URDFIssue]
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Issues")
                    .font(.headline)
                Spacer()
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if issues.isEmpty {
                Text("No issues.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(issues.indices, id: \.self) { idx in
                    IssueRow(issue: issues[idx])
                }
                .listStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

private struct IssueRow: View {
    let issue: URDFIssue

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(issue.severity.rawValue.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                    if let file = issue.file {
                        Text(file)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let line = issue.line {
                        Text("L\(line)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let tag = issue.tag {
                        Text("<\(tag)>")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(issue.message)
                    .font(.caption)
                if let hint = issue.hint, !hint.isEmpty {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
