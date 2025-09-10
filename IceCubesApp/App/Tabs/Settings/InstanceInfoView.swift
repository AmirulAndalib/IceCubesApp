import DesignSystem
import Models
import NukeUI
import SwiftUI

struct InstanceInfoView: View {
  @Environment(Theme.self) private var theme

  let instance: Instance

  var body: some View {
    Form {
      InstanceInfoSection(instance: instance)
    }
    .navigationTitle("instance.info.navigation-title")
    #if !os(visionOS)
      .scrollContentBackground(.hidden)
      .background(theme.secondaryBackgroundColor)
    #endif
  }
}

public struct InstanceInfoSection: View {
  @Environment(Theme.self) private var theme

  let instance: Instance

  public var body: some View {
    Section("instance.info.section.info") {
      LabeledContent("instance.info.name", value: instance.title)
      if instance.shortDescription != nil {
        Text(instance.shortDescription!)
      } else if instance.description != nil {
        Text(instance.description!)
      }
      LabeledContent("instance.info.email", value: instance.contact.email)
      LabeledContent("instance.info.version") {
        Text(instance.version).monospaced()
      }
      if let apiVersions = instance.apiVersions {
        LabeledContent("API Versions") {
          Text(apiVersions.mastodon.map { String($0) } ?? "Unknown").monospaced()
        }
      }
      if let activeMonth = instance.usage?.users?.activeMonth {
        LabeledContent("Monthly Active Users", value: format(activeMonth))
      }
    }
    #if !os(visionOS)
      .listRowBackground(theme.primaryBackgroundColor)
    #endif

    if let rules = instance.rules {
      Section("instance.info.section.rules") {
        ForEach(rules) { rule in
          Text(rule.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
      }
      #if !os(visionOS)
        .listRowBackground(theme.primaryBackgroundColor)
      #endif
    }
  }

  private func format(_ int: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: int))!
  }
}
