import SwiftUI

struct AuthView: View {
    @EnvironmentObject var session: SessionStore

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var displayName = ""
    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text("wyd?")
                            .font(.system(size: 56, weight: .black, design: .rounded))
                        Text("Find your people. Discover your next event.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 48)
                    .padding(.bottom, 24)

                    VStack(spacing: 12) {
                        if isSignUp {
                            TextField("Username (e.g. molly)", text: $username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            TextField("Display name", text: $displayName)
                                .textContentType(.name)
                                .textFieldStyle(.roundedBorder)
                        }
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        SecureField("Password", text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        submit()
                    } label: {
                        HStack {
                            if isBusy { ProgressView().tint(.white) }
                            Text(isSignUp ? "Create account" : "Sign in")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || email.isEmpty || password.count < 6 || (isSignUp && username.isEmpty))

                    Button(isSignUp ? "Already have an account? Sign in" : "New here? Create an account") {
                        withAnimation { isSignUp.toggle() }
                        error = nil
                    }
                    .font(.footnote)
                }
                .padding(.horizontal, 28)
            }
            .navigationBarHidden(true)
        }
    }

    private func submit() {
        isBusy = true
        error = nil
        Task {
            do {
                if isSignUp {
                    try await session.signUp(email: email, password: password, username: username, displayName: displayName)
                } else {
                    try await session.signIn(email: email, password: password)
                }
            } catch {
                self.error = error.localizedDescription
            }
            isBusy = false
        }
    }
}

#Preview {
    AuthView().environmentObject(SessionStore())
}
