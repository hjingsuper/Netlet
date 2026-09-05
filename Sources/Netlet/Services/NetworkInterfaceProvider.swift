import Darwin
import Foundation
import SystemConfiguration

struct NetworkInterfaceSnapshot: Sendable {
    let counters: [String: InterfaceByteCounters]
    let interfaces: [NetworkInterfaceDescriptor]
    let primaryInterfaceName: String?
}

enum NetworkInterfaceProvider {
    static func snapshot() -> NetworkInterfaceSnapshot {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else {
            return NetworkInterfaceSnapshot(counters: [:], interfaces: [], primaryInterfaceName: nil)
        }
        defer { freeifaddrs(addresses) }

        let displayNames = systemDisplayNames()
        var counters: [String: InterfaceByteCounters] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let current = pointer {
            let interface = current.pointee
            defer { pointer = interface.ifa_next }

            guard
                let address = interface.ifa_addr,
                Int32(address.pointee.sa_family) == AF_LINK,
                let dataPointer = interface.ifa_data
            else { continue }

            let flags = Int32(interface.ifa_flags)
            guard
                flags & IFF_UP != 0,
                flags & IFF_RUNNING != 0,
                flags & IFF_LOOPBACK == 0
            else { continue }

            let name = String(cString: interface.ifa_name)
            guard !shouldExclude(name) else { continue }

            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            counters[name] = InterfaceByteCounters(
                received: UInt64(data.ifi_ibytes),
                sent: UInt64(data.ifi_obytes)
            )
        }

        let descriptors = counters.keys
            .map { name in
                NetworkInterfaceDescriptor(
                    systemName: name,
                    localizedName: displayNames[name] ?? inferredDisplayName(for: name)
                )
            }
            .sorted { lhs, rhs in
                let leftScore = preferenceScore(for: lhs.systemName)
                let rightScore = preferenceScore(for: rhs.systemName)
                if leftScore != rightScore { return leftScore < rightScore }
                return lhs.systemName.localizedStandardCompare(rhs.systemName) == .orderedAscending
            }

        return NetworkInterfaceSnapshot(
            counters: counters,
            interfaces: descriptors,
            primaryInterfaceName: primaryInterfaceName()
        )
    }

    static func selectedInterface(
        from snapshot: NetworkInterfaceSnapshot,
        selection: InterfaceSelection
    ) -> String? {
        switch selection {
        case let .named(name):
            return snapshot.counters[name] == nil ? nil : name
        case .automatic:
            if let primary = snapshot.primaryInterfaceName,
               snapshot.counters[primary] != nil
            {
                return primary
            }
            return snapshot.interfaces.first?.systemName
        }
    }

    private static func primaryInterfaceName() -> String? {
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            guard
                let value = SCDynamicStoreCopyValue(nil, key as CFString) as? [String: Any],
                let name = value["PrimaryInterface"] as? String,
                !name.isEmpty
            else { continue }
            return name
        }
        return nil
    }

    private static func systemDisplayNames() -> [String: String] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return [:]
        }

        return interfaces.reduce(into: [:]) { result, interface in
            guard
                let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?,
                let displayName = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            else { return }
            result[bsdName] = displayName
        }
    }

    private static func shouldExclude(_ name: String) -> Bool {
        name == "lo0" ||
            name.hasPrefix("awdl") ||
            name.hasPrefix("llw") ||
            name.hasPrefix("anpi")
    }

    private static func inferredDisplayName(for name: String) -> String {
        if name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec") {
            return "VPN"
        }
        if name.hasPrefix("en") {
            return "Network"
        }
        if name.hasPrefix("bridge") {
            return "Bridge"
        }
        return name
    }

    private static func preferenceScore(for name: String) -> Int {
        if name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec") { return 0 }
        if name.hasPrefix("en") { return 1 }
        if name.hasPrefix("bridge") { return 2 }
        return 3
    }
}
