import SwiftUI

struct SettingsRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var tintColor: Color = .accentColor
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(tintColor)
                .frame(width: 28, height: 28)
                .background(tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
