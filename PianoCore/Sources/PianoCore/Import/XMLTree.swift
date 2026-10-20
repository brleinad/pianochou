import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A tiny in-memory XML tree. Foundation's `XMLDocument` is macOS-only, so we build our own
/// from `XMLParser` events, which exist on iOS, macOS and Linux.
final class XNode {
    let name: String
    let attributes: [String: String]
    var children: [XNode] = []
    var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func child(_ name: String) -> XNode? { children.first { $0.name == name } }
    func children(_ name: String) -> [XNode] { children.filter { $0.name == name } }
    var value: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    func string(_ name: String) -> String? { child(name)?.value }
    func int(_ name: String) -> Int? { string(name).flatMap { Int($0) } }
    func double(_ name: String) -> Double? { string(name).flatMap { Double($0) } }
}

enum XMLTree {
    struct ParseError: Error {
        let line: Int
        let message: String
    }

    static func parse(_ data: Data) throws -> XNode {
        let builder = Builder()
        let parser = XMLParser(data: data)
        // Never fetch the MusicXML DTD from the network.
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw ParseError(line: parser.lineNumber, message: parser.parserError?.localizedDescription ?? "empty document")
        }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var stack: [XNode] = []
        var root: XNode?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            let node = XNode(name: name, attributes: attributes)
            stack.last?.children.append(node)
            stack.append(node)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let node = stack.removeLast()
            if stack.isEmpty { root = node }
        }
    }
}
