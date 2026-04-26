import Foundation

enum ScheduledSendStore {
    private static let key = "gmac.scheduledSends"

    static func load() -> [ScheduledSendEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([ScheduledSendEntry].self, from: data)
        else { return [] }
        return entries
    }

    static func add(_ entry: ScheduledSendEntry) {
        var entries = load()
        entries.append(entry)
        persist(entries)
    }

    static func remove(id: UUID) {
        persist(load().filter { $0.id != id })
    }

    private static func persist(_ entries: [ScheduledSendEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
