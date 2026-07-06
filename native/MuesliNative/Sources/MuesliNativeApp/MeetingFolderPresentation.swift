import Foundation
import MuesliCore

struct FolderTreePresentation {
    let visibleFolders: [MeetingFolder]
    let depthByID: [Int64: Int]
    let childrenByParent: [Int64: [Int64]]

    init(folders: [MeetingFolder], collapsedFolderIDs: Set<Int64>) {
        let byID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var childrenByParent: [Int64: [Int64]] = [:]
        for folder in folders {
            if let parentID = folder.parentID {
                childrenByParent[parentID, default: []].append(folder.id)
            }
        }

        var depthCache: [Int64: Int] = [:]
        func depth(for folder: MeetingFolder, visited: Set<Int64> = []) -> Int {
            if let cached = depthCache[folder.id] { return cached }
            guard let parentID = folder.parentID,
                  let parent = byID[parentID],
                  !visited.contains(folder.id) else {
                depthCache[folder.id] = 0
                return 0
            }
            var nextVisited = visited
            nextVisited.insert(folder.id)
            let value = 1 + depth(for: parent, visited: nextVisited)
            depthCache[folder.id] = value
            return value
        }

        var hiddenCache: [Int64: Bool] = [:]
        func isHidden(_ folder: MeetingFolder, visited: Set<Int64> = []) -> Bool {
            if let cached = hiddenCache[folder.id] { return cached }
            guard let parentID = folder.parentID,
                  let parent = byID[parentID],
                  !visited.contains(folder.id) else {
                hiddenCache[folder.id] = false
                return false
            }
            if collapsedFolderIDs.contains(parentID) {
                hiddenCache[folder.id] = true
                return true
            }
            var nextVisited = visited
            nextVisited.insert(folder.id)
            let hidden = isHidden(parent, visited: nextVisited)
            hiddenCache[folder.id] = hidden
            return hidden
        }

        var computedDepths: [Int64: Int] = [:]
        for folder in folders {
            computedDepths[folder.id] = depth(for: folder)
        }

        self.visibleFolders = folders.filter { !isHidden($0) }
        self.depthByID = computedDepths
        self.childrenByParent = childrenByParent
    }

    func depth(of folder: MeetingFolder) -> Int {
        depthByID[folder.id] ?? 0
    }

    func hasChildren(_ folderID: Int64) -> Bool {
        !(childrenByParent[folderID] ?? []).isEmpty
    }
}
