#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct AppLockOverlayView: View {
    let appName: String
    @ObservedObject var lockManager: AppLockManager
    let hasFaceID: Bool
    let hasTouchID: Bool
    let hasPassword: Bool
    let onFaceID: () -> Void
    let onTouchID: () -> Void
    let onSubmitPassword: (String) -> Bool
    let onQuit: (() -> Void)?
    var quitButtonTitle: String = "Quit App"
    @State private var password = ""
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill").font(.system(size: 56)).foregroundStyle(.purple)
            Text("\(appName) is locked").font(.largeTitle.bold())
            if hasTouchID {
                Button("Unlock with system authentication", action: onTouchID)
                    .disabled(lockManager.isAuthenticating)
            }
            if hasPassword {
                SecureField("Mac login password", text: $password).frame(width: 280)
                    .onSubmit(submit)
                Button("Unlock with password", action: submit)
                    .disabled(password.isEmpty || lockManager.isAuthenticating)
            }
            if let message = lockManager.authenticationError {
                Text(message).foregroundStyle(.red).multilineTextAlignment(.center).frame(maxWidth: 400)
            }
            if lockManager.isAuthenticating { ProgressView() }
            if let onQuit { Button(quitButtonTitle, action: onQuit).keyboardShortcut(.cancelAction) }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    private func submit() {
        let attempt = password
        password = ""
        _ = onSubmitPassword(attempt)
    }
}
#endif
