import SwiftUI

/// Shown in place of the whole app when the local `ModelContainer` couldn't be
/// opened. No SwiftData error detail is shown — `AppStartupModel.State
/// .persistenceFailure` carries none to show, by design.
struct StartupFailureView: View {
  let onRetry: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Text("Step Mossaic couldn't open its local cache.")
        .font(.headline)
        .multilineTextAlignment(.center)
      Text("Your Health data is not affected.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button("Try Again", action: onRetry)
        .buttonStyle(.borderedProminent)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview {
  StartupFailureView(onRetry: {})
}
