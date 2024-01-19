import DesignSystem
import Models
import Nuke
import NukeUI
import SwiftUI

@MainActor
public struct StatusRowCardView: View {
  @Environment(\.openURL) private var openURL
  @Environment(\.isInCaptureMode) private var isInCaptureMode: Bool

  @Environment(Theme.self) private var theme

  let card: Card

  public init(card: Card) {
    self.card = card
  }

  private var maxWidth: CGFloat? {
    if theme.statusDisplayStyle == .medium {
      return 300
    }
    return nil
  }

  private func imageWidthFor(proxy: GeometryProxy) -> CGFloat {
    if theme.statusDisplayStyle == .medium, let maxWidth {
      return maxWidth
    }
    return proxy.frame(in: .local).width
  }

  private var imageHeight: CGFloat {
    if theme.statusDisplayStyle == .medium {
      return 100
    }
    return 200
  }

  public var body: some View {
    Button {
      if let url = URL(string: card.url) {
        openURL(url)
      }
    } label: {
      if let title = card.title, let url = URL(string: card.url) {
        VStack(alignment: .leading, spacing: 0) {
          let sitesWithIcons = ["apps.apple.com", "music.apple.com", "open.spotify.com"]
          if (UIDevice.current.userInterfaceIdiom == .pad ||
              UIDevice.current.userInterfaceIdiom == .mac ||
              UIDevice.current.userInterfaceIdiom == .vision),
             let host = url.host(), sitesWithIcons.contains(host) {
            iconLinkPreview(title, url)
          } else {
            defaultLinkPreview(title, url)
          }
        }
        .frame(maxWidth: maxWidth)
        .fixedSize(horizontal: false, vertical: true)
        #if os(visionOS)
        .background(.background)
        .hoverEffect()
        #else
        .background(theme.secondaryBackgroundColor)
        #endif
        .cornerRadius(10)
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(.gray.opacity(0.35), lineWidth: 1)
        )
        .contextMenu {
          ShareLink(item: url) {
            Label("status.card.share", systemImage: "square.and.arrow.up")
          }
          Button { openURL(url) } label: {
            Label("status.action.view-in-browser", systemImage: "safari")
          }
          Divider()
          Button {
            UIPasteboard.general.url = url
          } label: {
            Label("status.card.copy", systemImage: "doc.on.doc")
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
        .accessibilityRemoveTraits(.isStaticText)
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func defaultLinkPreview(_ title: String, _ url: URL) -> some View {
    if let imageURL = card.image, !isInCaptureMode {
      DefaultPreviewImage(url: imageURL, originalWidth: card.width, originalHeight: card.height)
    }

    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.scaledHeadline)
        .lineLimit(1)
      if let description = card.description, !description.isEmpty {
        Text(description)
          .font(.scaledFootnote)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
      Text(url.host() ?? url.absoluteString)
        .font(.scaledFootnote)
        .foregroundColor(theme.tintColor)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
  }

  private func iconLinkPreview(_ title: String, _ url: URL) -> some View {
    // ..where the image is known to be a square icon
    HStack {
      if let imageURL = card.image, !isInCaptureMode {
        LazyResizableImage(url: imageURL) { state, _ in
          if let image = state.image {
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: imageHeight, height: imageHeight)
              .clipped()
          } else if state.isLoading {
            Rectangle()
              .fill(Color.gray)
              .frame(width: imageHeight, height: imageHeight)
          }
        }
        // This image is decorative
        .accessibilityHidden(true)
        .frame(width: imageHeight, height: imageHeight)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.scaledHeadline)
          .lineLimit(3)
        if let description = card.description, !description.isEmpty {
          Text(description)
            .font(.scaledBody)
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }
        Text(url.host() ?? url.absoluteString)
          .font(.scaledFootnote)
          .foregroundColor(theme.tintColor)
          .lineLimit(1)
      }.padding(16)
    }
  }
}

struct DefaultPreviewImage: View {
  @Environment(Theme.self) private var theme
  
  let url: URL
  let originalWidth: CGFloat
  let originalHeight: CGFloat

  var body: some View {
    _Layout(originalWidth: originalWidth, originalHeight: originalHeight) {
      LazyResizableImage(url: url) { state, _ in
        Rectangle()
          .fill(theme.secondaryBackgroundColor)
          .overlay {
            if let image = state.image {
              image.resizable().scaledToFill()
            }
          }
      }
      .accessibilityHidden(true) // This image is decorative
      .clipped()
    }
  }

  private struct _Layout: Layout {
    let originalWidth: CGFloat
    let originalHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
      guard !subviews.isEmpty else { return CGSize.zero }
      return calculateSize(proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
      guard let view = subviews.first else { return }

      let size = calculateSize(proposal)
      view.place(at: bounds.origin, proposal: ProposedViewSize(size))
    }

    private func calculateSize(_ proposal: ProposedViewSize) -> CGSize {
      return switch (proposal.width, proposal.height) {
      case (nil, nil):
        CGSize(width: originalWidth, height: originalWidth)
      case let (nil, .some(height)):
        CGSize(width: originalWidth, height: min(height, originalWidth))
      case (0, _):
        CGSize.zero
      case let (.some(width), _):
        CGSize(width: width, height: width / originalWidth * originalHeight)
      }
    }
  }
}
