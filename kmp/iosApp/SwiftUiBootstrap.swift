import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MiGestor KMP iOS")
                .font(.title2)
            Text("Conecta aquí los ViewModels compartidos del módulo shared.")
                .foregroundColor(.secondary)
        }
        .padding(16)
    }
}
