import Foundation

/// Three-way merges for account sync. `base` is what this device last synced:
/// a change made on either side since then is kept, and when both sides changed
/// the same thing, this device (`local`) wins. With no base yet (first sync on
/// this device) lists are combined and single values come from the account.
enum Merge {
    static func value<T: Equatable>(local: T, remote: T?, base: T?) -> T {
        guard let remote else { return local }
        // A device's first sync joins an existing account: the account's choice
        // (theme, class order) comes back instead of being replaced by defaults.
        guard let base else { return remote }
        return local == base ? remote : local
    }

    static func set<T: Hashable>(local: Set<T>, remote: Set<T>, base: Set<T>?) -> Set<T> {
        guard let base else { return local.union(remote) }
        let added = remote.subtracting(base)
        let removed = base.subtracting(remote)
        return local.union(added).subtracting(removed.subtracting(local.subtracting(base)))
    }

    static func map<K: Hashable, V: Equatable>(local: [K: V], remote: [K: V], base: [K: V]?) -> [K: V] {
        guard let base else { return remote.merging(local) { _, mine in mine } }
        var out: [K: V] = [:]
        for key in Set(local.keys).union(remote.keys).union(base.keys) {
            let l = local[key], r = remote[key], b = base[key]
            out[key] = (l == b) ? r : l
        }
        return out
    }
}
