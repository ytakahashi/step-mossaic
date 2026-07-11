import SwiftUI

/// Small, non-blocking indicator that the shared sync failed to update a
/// section that is still rendering its last-good cached content.
///
/// Distinct from a section's own no-cache failed state, which replaces the
/// content instead of sitting above it. Shared between Home and Shelf so the
/// two screens use identical copy and layout for the same situation; each
/// section decides for itself whether it has content to show this above.
struct SyncFailureBanner: View {
  let onRetry: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text("Couldn't update your step data.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Button("Try Again", action: onRetry)
        .font(.caption)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
  }
}
