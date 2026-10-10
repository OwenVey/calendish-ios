import SwiftUI

extension View {
    /// Native alerts use a neutral tint for secondary actions, including Cancel. The system's
    /// default action retains the app's accent fill; destructive roles retain their red color.
    /// An independent presenter keeps this tint from affecting the screen's ordinary controls.
    func calendishAlert<Actions: View, Message: View>(
        _ title: String, isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        background {
            Color.clear.frame(width: 0, height: 0)
                .alert(Text(title), isPresented: isPresented, actions: actions, message: message)
                .tint(Color.primary)
        }
    }

    func calendishAlert<Data, Actions: View, Message: View>(
        _ title: String, isPresented: Binding<Bool>, presenting data: Data?,
        @ViewBuilder actions: @escaping (Data) -> Actions,
        @ViewBuilder message: @escaping (Data) -> Message
    ) -> some View {
        background {
            Color.clear.frame(width: 0, height: 0)
                .alert(Text(title), isPresented: isPresented, presenting: data, actions: actions, message: message)
                .tint(Color.primary)
        }
    }

    /// Presents while `item` holds a value and clears it on dismissal.
    func calendishAlert<Item, Actions: View, Message: View>(
        _ title: String, item: Binding<Item?>,
        @ViewBuilder actions: @escaping (Item) -> Actions,
        @ViewBuilder message: @escaping (Item) -> Message
    ) -> some View {
        background {
            Color.clear.frame(width: 0, height: 0)
                .alert(title, item: item, actions: actions, message: message)
                .tint(Color.primary)
        }
    }

    /// Shared title and list spacing for top-level tab screens, so switching tabs never shifts the header or first section.
    /// The zero top margin drops the grouped list's default gap, so content starts where a search field would.
    func tabRootStyle() -> some View {
        toolbarTitleDisplayMode(.inlineLarge).listSectionSpacing(.compact).contentMargins(.top, 0, for: .scrollContent)
    }

    /// Bar buttons stay monochrome like the system apps; only a screen's primary action (a prominent
    /// glass button or a sheet's confirmation) carries the accent. Menus get the same through `CalendishMenuStyle`.
    func toolbarGlyph() -> some View {
        tint(nil)
    }

    /// Context menus take their item color from the tint where they're attached, which is basil app-wide,
    /// so the menu gets the same neutral rendering as `CalendishMenuStyle` while the row keeps basil.
    /// Destructive roles keep their red.
    func calendishContextMenu<MenuItems: View>(@ViewBuilder menuItems: () -> MenuItems) -> some View {
        tint(CalendishStyle.accent).contextMenu(menuItems: menuItems).tint(nil)
    }

    func calendishContextMenu<MenuItems: View, Preview: View>(
        @ViewBuilder menuItems: () -> MenuItems, @ViewBuilder preview: () -> Preview
    ) -> some View {
        tint(CalendishStyle.accent).contextMenu(menuItems: menuItems, preview: preview).tint(nil)
    }
}
