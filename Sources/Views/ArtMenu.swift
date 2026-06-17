import SwiftUI

/// Reusable menu content: the ASCII-art catalog as grouped submenus. Drop inside
/// a `Menu { ArtMenu { … } }` or a `.contextMenu`.
struct ArtMenu: View {
    @Environment(AppModel.self) private var model
    let send: (ArtLine) -> Void

    var body: some View {
        if !model.customArt.isEmpty {
            Menu("My Art") {
                ForEach(model.customArt) { art in
                    Button(art.name) { send(art) }
                }
            }
            Divider()
        }
        ForEach(ArtCatalog.groups, id: \.name) { group in
            Menu(group.name) {
                ForEach(group.lines) { art in
                    Button(art.name) { send(art) }
                }
            }
        }
    }
}
