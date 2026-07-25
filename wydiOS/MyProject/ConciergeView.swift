import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
    var events: [Recommendation] = []
    var suggestions: [String] = []
}

struct ConciergeView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var locationManager: LocationManager

    @State private var messages: [ChatMessage] = [
        ChatMessage(
            isUser: false,
            text: "Hey! I'm your WYD concierge. Ask me what's happening, where your friends are, or what you should do next.",
            suggestions: ConciergeEngine.defaultSuggestions)
    ]
    @State private var input = ""
    @State private var isThinking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { message in
                                MessageBubble(message: message, onSuggestion: send, onRSVP: rsvp)
                                    .id(message.id)
                            }
                            if isThinking {
                                HStack {
                                    ProgressView()
                                    Text("thinking…").foregroundStyle(.secondary)
                                }
                                .font(.footnote)
                                .padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("wyd?", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { send(input) }
                    Button {
                        send(input)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("wyd?")
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking, let userID = session.profile?.id else { return }
        input = ""
        messages.append(ChatMessage(isUser: true, text: trimmed))
        isThinking = true
        Task {
            let reply = await ConciergeEngine.respond(to: trimmed, userID: userID, reference: locationManager.location)
            messages.append(ChatMessage(isUser: false, text: reply.text, events: reply.events, suggestions: reply.suggestions))
            isThinking = false
        }
    }

    private func rsvp(_ event: Recommendation) {
        guard let userID = session.profile?.id else { return }
        Task {
            try? await APIClient.shared.insert("rsvps", row: [
                "event_id": event.id.uuidString,
                "user_id": userID.uuidString,
                "status": "going"
            ])
            messages.append(ChatMessage(
                isUser: false,
                text: "You're in for **\(event.title)**! Your circles will see you're going. 🎉"))
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let onSuggestion: (String) -> Void
    let onRSVP: (Recommendation) -> Void

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            Text(LocalizedStringKey(message.text)) // enables **bold** markdown
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.isUser ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(message.isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 300, alignment: message.isUser ? .trailing : .leading)

            ForEach(message.events) { event in
                EventCard(event: event, onRSVP: { onRSVP(event) })
            }

            if !message.suggestions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(message.suggestions, id: \.self) { suggestion in
                        Button(suggestion) { onSuggestion(suggestion) }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }
}

struct EventCard: View {
    let event: Recommendation
    let onRSVP: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: event.categoryIcon)
                    .foregroundStyle(event.categoryColor)
                Text(event.title).font(.headline)
            }
            Text("\(event.venue ?? "TBD") · \(event.startsAt.wydDay) \(event.startsAt.wydTime)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if event.friendsGoing.value > 0 {
                Text("👥 \(event.friendNames.prefix(3).joined(separator: ", "))\(event.friendsGoing.value > 3 ? " +\(event.friendsGoing.value - 3) more" : "") going")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Join", action: onRSVP)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: 300, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Minimal wrapping layout for suggestion chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    ConciergeView()
        .environmentObject(SessionStore())
        .environmentObject(LocationManager())
}
