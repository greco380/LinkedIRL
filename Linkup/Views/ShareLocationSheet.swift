import SwiftUI

struct ShareLocationSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.linkupTheme) private var theme
    @State private var hours: Int = 2
    @State private var eventName = ""
    private let options = [1, 2, 3, 4, 8, 12, 15]

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(theme.textQuaternary.opacity(0.55))
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            VStack(spacing: 5) {
                Text("Share your location")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(theme.textPrimary)
                Text("Your network can see you on the map for as long as you choose.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(hours)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(theme.primary)
                    Text(hours == 1 ? "hour" : "hours")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(theme.primary)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(options, id: \.self) { option in
                            Button {
                                hours = option
                            } label: {
                                Text("\(option)")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(hours == option ? .white : theme.textSecondary)
                                    .frame(width: 48, height: 48)
                                    .background(hours == option ? theme.primary : theme.bgSecondary, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Event")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.textSecondary)

                TextField("e.g. SaaStr Annual 2026", text: $eventName)
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .foregroundStyle(theme.textPrimary)
                    .background(theme.bgSecondary, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(SampleData.eventSuggestions.prefix(3), id: \.self) { suggestion in
                            Button(suggestion) {
                                eventName = suggestion
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.primaryDark)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(theme.primaryLight, in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            PrimaryButton(title: "Share for \(hours) \(hours == 1 ? "hour" : "hours")") {
                store.startSharing(hours: hours, eventName: eventName)
                dismiss()
            }

            Button("Cancel") {
                dismiss()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .background(theme.bg.ignoresSafeArea())
        .onAppear {
            hours = options.contains(store.settings.defaultShareHours) ? store.settings.defaultShareHours : 2
        }
    }
}
