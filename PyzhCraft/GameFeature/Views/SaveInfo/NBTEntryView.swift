import SwiftUI

struct NBTEntryView: View {
    let key: String
    let value: Any
    @Binding var expandedKeys: Set<String>
    let indentLevel: Int
    let fullKey: String
    @State private var isHovered = false

    init(key: String, value: Any, expandedKeys: Binding<Set<String>>, indentLevel: Int, fullKey: String? = nil) {
        self.key = key
        self.value = value
        self._expandedKeys = expandedKeys
        self.indentLevel = indentLevel
        self.fullKey = fullKey ?? key
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let dict = value as? [String: Any] {
                NBTDisclosureButton(
                    isExpanded: expandedKeys.contains(fullKey),
                    label: key,
                    suffix: "{\(dict.count)}",
                    indentLevel: indentLevel,
                    isHovered: $isHovered
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expandedKeys.contains(fullKey) {
                            expandedKeys.remove(fullKey)
                        } else {
                            expandedKeys.insert(fullKey)
                        }
                    }
                }

                if expandedKeys.contains(fullKey) {
                    ForEach(Array(dict.keys.sorted()), id: \.self) { subKey in
                        if let subValue = dict[subKey] {
                            Self(
                                key: subKey,
                                value: subValue,
                                expandedKeys: $expandedKeys,
                                indentLevel: indentLevel + 1,
                                fullKey: "\(fullKey).\(subKey)"
                            )
                        }
                    }
                }
            } else if let array = value as? [Any] {
                NBTDisclosureButton(
                    isExpanded: expandedKeys.contains(fullKey),
                    label: key,
                    suffix: "[\(array.count)]",
                    indentLevel: indentLevel,
                    isHovered: $isHovered
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expandedKeys.contains(fullKey) {
                            expandedKeys.remove(fullKey)
                        } else {
                            expandedKeys.insert(fullKey)
                        }
                    }
                }

                if expandedKeys.contains(fullKey) {
                    ForEach(Array(array.enumerated()), id: \.offset) { index, item in
                        let arrayItemKey = "\(fullKey)[\(index)]"
                        if let itemDict = item as? [String: Any] {
                            Self(
                                key: "[\(index)]",
                                value: itemDict,
                                expandedKeys: $expandedKeys,
                                indentLevel: indentLevel + 1,
                                fullKey: arrayItemKey
                            )
                        } else {
                            NBTValueRow(
                                label: "[\(index)]",
                                value: formatNBTValue(item),
                                indentLevel: indentLevel + 1
                            )
                        }
                    }
                }
            } else {
                NBTValueRow(
                    label: key,
                    value: formatNBTValue(value),
                    indentLevel: indentLevel
                )
            }
        }
    }

    private func formatNBTValue(_ value: Any) -> String {
        if let v = value as? String { return "\"\(v)\"" }
        if let v = value as? Bool { return v ? "true" : "false" }
        if let v = value as? Int8 { return "\(v)b" }
        if let v = value as? Int16 { return "\(v)s" }
        if let v = value as? Int32 { return "\(v)" }
        if let v = value as? Int64 { return "\(v)L" }
        if let v = value as? Int { return "\(v)" }
        if let v = value as? Double { return "\(v)d" }
        if let v = value as? Float { return "\(v)f" }
        if let v = value as? Data { return "Data(\(v.count) bytes)" }
        if let v = value as? URL { return v.path }
        return String(describing: value)
    }
}
