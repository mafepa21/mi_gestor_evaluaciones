import SwiftUI

struct BackupsWorkspaceView: View {
    @Binding var selectedClassId: Int64?
    
    var body: some View {
        BackupCenterView()
    }
}
