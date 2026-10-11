import SwiftUI

/// Lays out views left to right, wrapping onto a new line when a row runs out of room.
/// Views in a row are centered vertically on each other.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let layout = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: layout.width, height: layout.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, layout.origins) {
            let size = measuredSize(subview, width: bounds.width)
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: ProposedViewSize(size))
        }
    }
    private func measuredSize(_ subview: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        return ideal.width > width ? subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) : ideal
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var row: [(index: Int, height: CGFloat)] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        func centerRow() {
            for item in row { origins[item.index].y += (rowHeight - item.height) / 2 }
            row = []
        }
        for subview in subviews {
            let size = measuredSize(subview, width: width)
            if x > 0, x + size.width > width {
                centerRow()
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            row.append((origins.count, size.height))
            origins.append(CGPoint(x: x, y: y))
            maxX = max(maxX, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        centerRow()
        return (origins, maxX, y + rowHeight)
    }
}
