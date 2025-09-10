import Foundation
import SwiftSoup
import SwiftUI

private enum CodingKeys: CodingKey {
  case htmlValue, asMarkdown, asRawText, statusesURLs, links, hadTrailingTags
}

public struct HTMLString: Codable, Equatable, Hashable, @unchecked Sendable {
  public var htmlValue: String = ""
  public var asMarkdown: String = ""
  public var asRawText: String = ""
  public var statusesURLs = [URL]()
  public private(set) var links = [Link]()
  public private(set) var hadTrailingTags = false

  public var asSafeMarkdownAttributedString: AttributedString = .init()
  private var main_regex: NSRegularExpression?
  private var underscore_regex: NSRegularExpression?
  public init(from decoder: Decoder) {
    var alreadyDecoded = false
    do {
      let container = try decoder.singleValueContainer()
      htmlValue = try container.decode(String.self)
    } catch {
      do {
        alreadyDecoded = true
        let container = try decoder.container(keyedBy: CodingKeys.self)
        htmlValue = try container.decode(String.self, forKey: .htmlValue)
        asMarkdown = try container.decode(String.self, forKey: .asMarkdown)
        asRawText = try container.decode(String.self, forKey: .asRawText)
        statusesURLs = try container.decode([URL].self, forKey: .statusesURLs)
        links = try container.decode([Link].self, forKey: .links)
        hadTrailingTags = (try? container.decode(Bool.self, forKey: .hadTrailingTags)) ?? false
      } catch {
        htmlValue = ""
      }
    }

    if !alreadyDecoded {
      // https://daringfireball.net/projects/markdown/syntax
      // Pre-escape \ ` _ * ~ and [ as these are the only
      // characters the markdown parser uses when it renders
      // to attributed text. Note that ~ for strikethrough is
      // not documented in the syntax docs but is used by
      // AttributedString.
      main_regex = try? NSRegularExpression(
        pattern: "([\\*\\`\\~\\[\\\\])", options: .caseInsensitive)
      // don't escape underscores that are between colons, they are most likely custom emoji
      underscore_regex = try? NSRegularExpression(
        pattern: "(?!\\B:[^:]*)(_)(?![^:]*:\\B)", options: .caseInsensitive)

      asMarkdown = ""
      do {
        let document: Document = try SwiftSoup.parse(htmlValue)
        var listCounters: [Int] = []
        handleNode(node: document, listCounters: &listCounters)

        document.outputSettings(OutputSettings().prettyPrint(pretty: false))
        try document.select("br").after("\n")
        try document.select("p").after("\n\n")
        let html = try document.html()
        var text =
          try SwiftSoup.clean(
            html, "", Whitelist.none(), OutputSettings().prettyPrint(pretty: false)) ?? ""
        // Remove the two last line break added after the last paragraph.
        if text.hasSuffix("\n\n") {
          _ = text.removeLast()
          _ = text.removeLast()
        }
        asRawText = (try? Entities.unescape(text)) ?? text

        if asMarkdown.hasPrefix("\n") {
          _ = asMarkdown.removeFirst()
        }

        // Remove trailing hashtags
        removeTrailingTags()

        // Regenerate attributed string after extracting tags
        do {
          let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
          asSafeMarkdownAttributedString = try AttributedString(
            markdown: asMarkdown, options: options)
        } catch {
          asSafeMarkdownAttributedString = AttributedString(stringLiteral: asMarkdown)
        }

      } catch {
        asRawText = htmlValue
      }
    } else {
      do {
        let options = AttributedString.MarkdownParsingOptions(
          allowsExtendedAttributes: true,
          interpretedSyntax: .inlineOnlyPreservingWhitespace)
        asSafeMarkdownAttributedString = try AttributedString(
          markdown: asMarkdown, options: options)
      } catch {
        asSafeMarkdownAttributedString = AttributedString(stringLiteral: htmlValue)
      }
    }
  }

  public init(stringValue: String, parseMarkdown: Bool = false) {
    htmlValue = stringValue
    asMarkdown = stringValue
    asRawText = stringValue
    statusesURLs = []

    if parseMarkdown {
      do {
        let options = AttributedString.MarkdownParsingOptions(
          allowsExtendedAttributes: true,
          interpretedSyntax: .inlineOnlyPreservingWhitespace)
        asSafeMarkdownAttributedString = try AttributedString(
          markdown: asMarkdown, options: options)
      } catch {
        asSafeMarkdownAttributedString = AttributedString(stringLiteral: htmlValue)
      }
    } else {
      asSafeMarkdownAttributedString = AttributedString(stringLiteral: htmlValue)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(htmlValue, forKey: .htmlValue)
    try container.encode(asMarkdown, forKey: .asMarkdown)
    try container.encode(asRawText, forKey: .asRawText)
    try container.encode(statusesURLs, forKey: .statusesURLs)
    try container.encode(links, forKey: .links)
    try container.encode(hadTrailingTags, forKey: .hadTrailingTags)
  }

  private mutating func removeTrailingTags() {
    // Check if the last paragraph consists only of hashtag links
    // Pattern matches hashtag links in the markdown format: [#tag](url)
    // Note: hashtag names can contain letters, numbers, and underscores
    let hashtagLinkPattern = #"\[#[\w]+\]\([^)]+\)"#
    guard let regex = try? NSRegularExpression(pattern: hashtagLinkPattern, options: []) else {
      return
    }

    // Split markdown by double newlines to get paragraphs
    let paragraphs = asMarkdown.split(separator: "\n\n", omittingEmptySubsequences: false).map {
      String($0)
    }
    guard !paragraphs.isEmpty else { return }

    // Check the last non-empty paragraph
    guard
      let lastParagraphIndex = paragraphs.lastIndex(where: {
        !$0.trimmingCharacters(in: .whitespaces).isEmpty
      })
    else { return }
    let lastParagraph = paragraphs[lastParagraphIndex].trimmingCharacters(
      in: .whitespacesAndNewlines)

    // Check if the entire paragraph consists only of hashtag links
    let range = NSRange(location: 0, length: lastParagraph.count)
    let matches = regex.matches(in: lastParagraph, options: [], range: range)

    // Reconstruct the paragraph from matches to see if it equals the original (minus whitespace)
    var reconstructed = ""
    var lastEnd = 0

    for match in matches {
      let matchRange = match.range

      // Check if there's non-whitespace content between matches
      if lastEnd < matchRange.location {
        let between = lastParagraph[
          lastParagraph.index(
            lastParagraph.startIndex, offsetBy: lastEnd)..<lastParagraph.index(
              lastParagraph.startIndex, offsetBy: matchRange.location)]
        if !between.trimmingCharacters(in: .whitespaces).isEmpty {
          // There's content between hashtags, so don't remove
          return
        }
      }

      if let range = Range(matchRange, in: lastParagraph) {
        reconstructed += lastParagraph[range]
      }
      lastEnd = matchRange.location + matchRange.length
    }

    // Check if there's content after the last match
    if lastEnd < lastParagraph.count {
      let after = lastParagraph[lastParagraph.index(lastParagraph.startIndex, offsetBy: lastEnd)...]
      if !after.trimmingCharacters(in: .whitespaces).isEmpty {
        // There's content after hashtags, so don't remove
        return
      }
    }

    // If we have matches and they constitute the entire paragraph, remove it
    if !matches.isEmpty && !reconstructed.isEmpty {
      hadTrailingTags = true

      // Remove the last paragraph from markdown
      var updatedParagraphs = Array(paragraphs)
      updatedParagraphs.remove(at: lastParagraphIndex)

      // Remove any trailing empty paragraphs
      while !updatedParagraphs.isEmpty
        && updatedParagraphs.last?.trimmingCharacters(in: .whitespaces).isEmpty == true
      {
        updatedParagraphs.removeLast()
      }

      asMarkdown = updatedParagraphs.joined(separator: "\n\n")

      // Also update asRawText to remove the hashtags
      // Split by double newlines
      let rawParagraphs = asRawText.split(separator: "\n\n", omittingEmptySubsequences: false).map {
        String($0)
      }
      if let lastRawIndex = rawParagraphs.lastIndex(where: {
        !$0.trimmingCharacters(in: .whitespaces).isEmpty
      }) {
        let lastRawParagraph = rawParagraphs[lastRawIndex]
        // Check if it contains hashtags
        if lastRawParagraph.contains("#") {
          var updatedRawParagraphs = Array(rawParagraphs)
          updatedRawParagraphs.remove(at: lastRawIndex)
          while !updatedRawParagraphs.isEmpty
            && updatedRawParagraphs.last?.trimmingCharacters(in: .whitespaces).isEmpty == true
          {
            updatedRawParagraphs.removeLast()
          }
          asRawText = updatedRawParagraphs.joined(separator: "\n\n")
        }
      }
    }
  }

  private mutating func handleNode(
    node: SwiftSoup.Node,
    indent: Int? = 0,
    skipParagraph: Bool = false,
    listCounters: inout [Int]
  ) {
    do {
      if let className = try? node.attr("class") {
        if className == "invisible" {
          // don't display
          return
        }

        if className == "ellipsis" {
          // descend into this one now and
          // append the ellipsis
          for nn in node.getChildNodes() {
            handleNode(node: nn, indent: indent, listCounters: &listCounters)
          }
          asMarkdown += "…"
          return
        }
      }

      if node.nodeName() == "p" {
        if asMarkdown.count > 0 && !skipParagraph {
          asMarkdown += "\n\n"
        }
      } else if node.nodeName() == "br" {
        if asMarkdown.count > 0 {  // ignore first opening <br>
          asMarkdown += "\n"
        }
        if (indent ?? 0) > 0 {
          asMarkdown += "\n"
        }
      } else if node.nodeName() == "a" {
        let href = try node.attr("href")
        if href != "" {
          if let url = URL(string: href) {
            if Int(url.lastPathComponent) != nil {
              statusesURLs.append(url)
            } else if url.host() == "www.threads.net" || url.host() == "threads.net",
              url.pathComponents.count == 4,
              url.pathComponents[2] == "post"
            {
              statusesURLs.append(url)
            }
          }
        }
        asMarkdown += "["
        let start = asMarkdown.endIndex
        // descend into this node now so we can wrap the
        // inner part of the link in the right markup
        for nn in node.getChildNodes() {
          handleNode(node: nn, listCounters: &listCounters)
        }
        let finish = asMarkdown.endIndex

        var linkRef = href

        // Try creating a URL from the string. If it fails, try URL encoding
        //   the string first.
        var url = URL(string: href)
        if url == nil {
          url = URL(string: href, encodePath: true)
        }
        if let linkUrl = url {
          linkRef = linkUrl.absoluteString
          let displayString = asMarkdown[start..<finish]
          links.append(Link(linkUrl, displayString: String(displayString)))
        }

        asMarkdown += "]("
        asMarkdown += linkRef
        asMarkdown += ")"

        return
      } else if node.nodeName() == "#text" {
        var txt = node.description

        txt = (try? Entities.unescape(txt)) ?? txt

        if let underscore_regex, let main_regex {
          //  This is the markdown escaper
          txt = main_regex.stringByReplacingMatches(
            in: txt, options: [], range: NSRange(location: 0, length: txt.count),
            withTemplate: "\\\\$1")
          txt = underscore_regex.stringByReplacingMatches(
            in: txt, options: [], range: NSRange(location: 0, length: txt.count),
            withTemplate: "\\\\$1")
        }
        // Strip newlines and line separators - they should be being sent as <br>s
        asMarkdown += txt.replacingOccurrences(of: "\n", with: "").replacingOccurrences(
          of: "\u{2028}", with: "")
      } else if node.nodeName() == "blockquote" {
        asMarkdown += "\n\n`"
        for nn in node.getChildNodes() {
          handleNode(node: nn, indent: indent, listCounters: &listCounters)
        }
        asMarkdown += "`"
        return
      } else if node.nodeName() == "strong" || node.nodeName() == "b" {
        asMarkdown += "**"
        for nn in node.getChildNodes() {
          handleNode(node: nn, indent: indent, listCounters: &listCounters)
        }
        asMarkdown += "**"
        return
      } else if node.nodeName() == "em" || node.nodeName() == "i" {
        asMarkdown += "_"
        for nn in node.getChildNodes() {
          handleNode(node: nn, indent: indent, listCounters: &listCounters)
        }
        asMarkdown += "_"
        return
      } else if node.nodeName() == "ul" || node.nodeName() == "ol" {

        if skipParagraph {
          asMarkdown += "\n"
        } else {
          asMarkdown += "\n\n"
        }

        var listCounters = listCounters

        if node.nodeName() == "ol" {
          listCounters.append(1)  // Start numbering for a new ordered list
        }

        for nn in node.getChildNodes() {
          handleNode(node: nn, indent: (indent ?? 0) + 1, listCounters: &listCounters)
        }

        if node.nodeName() == "ol" {
          listCounters.removeLast()
        }

        return
      } else if node.nodeName() == "li" {
        asMarkdown += "   "
        if let indent, indent > 1 {
          for _ in 0..<indent {
            asMarkdown += "   "
          }
          asMarkdown += "- "
        }

        if listCounters.isEmpty {
          asMarkdown += "• "
        } else {
          let currentIndex = listCounters.count - 1
          asMarkdown += "\(listCounters[currentIndex]). "
          listCounters[currentIndex] += 1
        }

        for nn in node.getChildNodes() {
          handleNode(node: nn, indent: indent, skipParagraph: true, listCounters: &listCounters)
        }
        asMarkdown += "\n"
        return
      }

      for n in node.getChildNodes() {
        handleNode(node: n, indent: indent, listCounters: &listCounters)
      }
    } catch {}
  }

  public struct Link: Codable, Hashable, Identifiable {
    public var id: Int { hashValue }
    public let url: URL
    public let displayString: String
    public let type: LinkType
    public let title: String

    init(_ url: URL, displayString: String) {
      self.url = url
      self.displayString = displayString

      switch displayString.first {
      case "@":
        type = .mention
        title = displayString
      case "#":
        type = .hashtag
        title = String(displayString.dropFirst())
      default:
        type = .url
        var hostNameUrl = url.host ?? url.absoluteString
        if hostNameUrl.hasPrefix("www.") {
          hostNameUrl = String(hostNameUrl.dropFirst(4))
        }
        title = hostNameUrl
      }
    }

    public enum LinkType: String, Codable {
      case url
      case mention
      case hashtag
    }
  }
}

extension URL {
  // It's common to use non-ASCII characters in URLs even though they're technically
  //   invalid characters. Every modern browser handles this by silently encoding
  //   the invalid characters on the user's behalf. However, trying to create a URL
  //   object with un-encoded characters will result in nil so we need to encode the
  //   invalid characters before creating the URL object. The unencoded version
  //   should still be shown in the displayed status.
  public init?(string: String, encodePath: Bool) {
    var encodedUrlString = ""
    if encodePath,
      string.starts(with: "http://") || string.starts(with: "https://"),
      var startIndex = string.firstIndex(of: "/")
    {
      startIndex = string.index(startIndex, offsetBy: 1)

      // We don't want to encode the host portion of the URL
      if var startIndex = string[startIndex...].firstIndex(of: "/") {
        encodedUrlString = String(string[...startIndex])
        while let endIndex = string[string.index(after: startIndex)...].firstIndex(of: "/") {
          let componentStartIndex = string.index(after: startIndex)
          encodedUrlString =
            encodedUrlString
            + (string[componentStartIndex...endIndex].addingPercentEncoding(
              withAllowedCharacters: .urlPathAllowed) ?? "")
          startIndex = endIndex
        }

        // The last part of the path may have a query string appended to it
        let componentStartIndex = string.index(after: startIndex)
        if let queryStartIndex = string[componentStartIndex...].firstIndex(of: "?") {
          encodedUrlString =
            encodedUrlString
            + (string[componentStartIndex..<queryStartIndex].addingPercentEncoding(
              withAllowedCharacters: .urlPathAllowed) ?? "")
          encodedUrlString =
            encodedUrlString
            + (string[queryStartIndex...].addingPercentEncoding(
              withAllowedCharacters: .urlQueryAllowed) ?? "")
        } else {
          encodedUrlString =
            encodedUrlString
            + (string[componentStartIndex...].addingPercentEncoding(
              withAllowedCharacters: .urlPathAllowed) ?? "")
        }
      }
    }
    if encodedUrlString.isEmpty {
      encodedUrlString = string
    }
    self.init(string: encodedUrlString)
  }
}
