import Foundation

struct FolderNode: Identifiable, Hashable {
    let id: String
    let name: String
    var children: [FolderNode]
    var series: [Series]
    
    var isLeaf: Bool {
        return children.isEmpty
    }
}

class FolderUtilities {
    static func buildTree(from seriesList: [Series], pathMap: [String: String]) -> [FolderNode] {
        
        // Helper to normalize path
        func getPathComponents(_ path: String) -> [String] {
            // Handle Windows paths (backslashes) and Unix (slashes)
            let standardPath = path.replacingOccurrences(of: "\\", with: "/")
            return standardPath.split(separator: "/").map { String($0) }.filter { !$0.isEmpty }
        }
        
        // 1. Find Common Prefix
        // We look at ALL paths to find the shared root directory (e.g. "H:/Comics/Marvel")
        let allPaths = seriesList.compactMap { pathMap[$0.id] }
        var commonPrefix: [String]? = nil
        
        for path in allPaths {
            let components = getPathComponents(path)
            // Just take the directory part (drop filename)
            // Ideally common prefix is about FOLDERS.
            let folderComponents = components.dropLast()
            
            if commonPrefix == nil {
                commonPrefix = Array(folderComponents)
            } else {
                // Reduce prefix
                var newPrefix: [String] = []
                let count = min(commonPrefix!.count, folderComponents.count)
                for i in 0..<count {
                    if commonPrefix![i] == folderComponents[i] {
                        newPrefix.append(commonPrefix![i])
                    } else {
                        break
                    }
                }
                commonPrefix = newPrefix
            }
            if commonPrefix?.isEmpty == true { break }
        }
        
        // Define clean root name based on prefix last component or "Library Root"
        let rootName = commonPrefix?.last ?? "Root"
        // Defines a node in the tree construction
        class Node {
            let name: String
            var children: [String: Node] = [:]
            var series: [Series] = []
            
            init(name: String) { self.name = name }
        }
        
        let root = Node(name: rootName)
        let prefixCount = commonPrefix?.count ?? 0
        
        // Pre-scan to identify all directory paths
        // This handles the case where a Series path (e.g. "RootFolder") matches a Directory path (parent of "RootFolder/Sub").
        // We want to place the "RootFolder" series INSIDE the "RootFolder" node, not as a sibling.
        var directoryPaths: Set<[String]> = []
        for series in seriesList {
            let fullPath = pathMap[series.id] ?? ""
            var components = getPathComponents(fullPath)
            
            // Apply Prefix Strip
            if prefixCount > 0 && components.count >= prefixCount {
                 components.removeFirst(prefixCount)
            }
            
            if !components.isEmpty {
                let dir = Array(components.dropLast())
                if !dir.isEmpty {
                    directoryPaths.insert(dir)
                }
            }
        }
        
        for series in seriesList {
            // Use path from map, fallback to empty
            let fullPath = pathMap[series.id] ?? ""
            let components = getPathComponents(fullPath)
            
            // Strip Common Prefix
            // We want the relative path from the library root.
            var relativeComponents = components
            if prefixCount > 0 && relativeComponents.count >= prefixCount {
                 // Check if it actually matches (it should)
                 // Then remove first N
                 relativeComponents.removeFirst(prefixCount)
            }
            
            // Logic to determine folder structure from file path
            var folderPathComponents: [String] = []
            if !relativeComponents.isEmpty {
                // Check if this Series path ITSELF is a known directory (from pre-scan)
                // If yes, this series belongs INSIDE that directory.
                if directoryPaths.contains(relativeComponents) {
                    folderPathComponents = relativeComponents
                } else {
                    folderPathComponents = Array(relativeComponents.dropLast()) // Normal file/series behavior
                }
            }
            
            // Walk the tree and place series in the correct node
            var currentNode = root
            
            for folderName in folderPathComponents {
                if let child = currentNode.children[folderName] {
                    currentNode = child
                } else {
                    let newChild = Node(name: folderName)
                    currentNode.children[folderName] = newChild
                    currentNode = newChild
                }
            }
            
            // Add series to this folder node
            currentNode.series.append(series)
        }
        
        // Post-Processing: Smart Collapse
        // We convert the Node tree to [FolderNode], effectively pruning/collapsing as we go.
        // Returns: (list of folders, list of promoted series)
        func convertAndCollapse(_ node: Node, idPrefix: String) -> ([FolderNode], [Series]) {
            var finalFolders: [FolderNode] = []
            var finalSeries: [Series] = node.series // Start with own series
            
            let sortedKeys = node.children.keys.sorted()
            
            for key in sortedKeys {
                let childNode = node.children[key]!
                let childId = idPrefix + "/" + key
                let (childFolders, childPromotedSeries) = convertAndCollapse(childNode, idPrefix: childId)
                
                // Logic:
                // If the child resulted in NO folders and exactly ONE promoted series,
                // and the Child Node itself had no series of its own (wait, childPromotedSeries includes child.series),
                // then we consider that child "Collapsible".
                
                // Actually, let's look at what the child returning means.
                // The child returns the content that should be displayed at THIS level.
                // If the child returns [Folder A], [Series B] -> We create a Folder for the child?
                // No, the child function processes the Child Node's contents.
                
                // Let's refine the return signature.
                // We are processing `childNode`.
                // We want to decide: Do we turn `childNode` into a `FolderNode`? Or do we steal its contents?
                
                // Case 1: Child has sub-folders (childFolders not empty).
                // -> Must be a FolderNode.
                
                // Case 2: Child has NO sub-folders, but multiple series.
                // -> Must be a FolderNode (to group them).
                
                // Case 3: Child has NO sub-folders and EXACTLY ONE series.
                // -> COLLAPSE. Return that series to the parent (me). Do not create FolderNode.
                
                // Smart Collapse: If child has NO subfolders, ONLY ONE series, AND names are similar.
                // This prevents "Double Visualization": Folder X -> Series X.
                // Use localized comparison for redundancy check.
                let seriesName = childPromotedSeries.first?.name ?? ""
                let isNameRedundant = !seriesName.isEmpty && (key.localizedCaseInsensitiveContains(seriesName) || seriesName.localizedCaseInsensitiveContains(key))
                
                let isCollapsible = childFolders.isEmpty && childPromotedSeries.count == 1 && isNameRedundant
                
                // DEBUG: Trace collapse decision
                if isCollapsible {
                    print("🔹 Collapsing folder '\(key)' -> '\(seriesName)' (Redundant Layer)")
                    finalSeries.append(contentsOf: childPromotedSeries)
                } else if !childFolders.isEmpty || !childPromotedSeries.isEmpty {
                    print("📁 Keeping folder '\(key)' (Folders: \(childFolders.count), Series: \(childPromotedSeries.count))")
                    // Create a FolderNode for this child
                    let folderNode = FolderNode(
                        id: childId,
                        name: key,
                        children: childFolders,
                        series: childPromotedSeries.sorted(by: { $0.name < $1.name })
                    )
                    finalFolders.append(folderNode)
                }
            }
            
            return (finalFolders, finalSeries)
        }
        
        let (rootFolders, rootSeries) = convertAndCollapse(root, idPrefix: "root")
        
        // Return a virtual root
        let combinedRoot = FolderNode(
            id: "virtual_root",
            name: "Root",
            children: rootFolders,
            series: rootSeries.sorted(by: { $0.name < $1.name })
        )
        
        return [combinedRoot]
    }
}

// MARK: - Download Helpers
extension FolderUtilities {
    static func countSeriesRecursive(node: FolderNode) -> Int {
        var count = node.series.count
        for child in node.children {
            count += countSeriesRecursive(node: child)
        }
        return count
    }
    
    // Returns a list of (Series, RelativePath) tuples for downloading
    // nodePath: The path OF the current node (e.g. "Marvel"). 
    // If empty, we start at root.
    static func collectSeriesForDownload(node: FolderNode, parentPath: String = "") -> [(series: Series, relativePath: String)] {
        var items: [(Series, String)] = []
        
        let currentPath = parentPath.isEmpty ? node.name : (parentPath + "/" + node.name)
        
        for series in node.series {
            items.append((series, currentPath))
        }
        
        for child in node.children {
            items.append(contentsOf: collectSeriesForDownload(node: child, parentPath: currentPath))
        }
        
        return items
    }
        
}
