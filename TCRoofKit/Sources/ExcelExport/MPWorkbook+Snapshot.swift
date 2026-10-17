import Foundation
import TCRoofCore

extension MPWorkbook {
    /// The progress a plan file held when the app last exported it, kept inside the file as a custom XML part (Excel keeps
    /// those as they are when it saves), so taking the file's progress later can tell what was changed in Excel since:
    /// a booking moved or cleared there, as against one the app made after the export (`Actual.merging`). Each exported
    /// copy carries its own, so several copies edited at once each merge from the right starting point.
    enum Snapshot {
        static let namespace = "urn:tcroof:mp-progress"
        static let relationshipID = "rIdTCRoofProgress"

        static func read(_ zip: ZipArchive) -> MasterSchedule.Actual? {
            guard let path = part(zip), let xml = zip.string(path), let body = content(xml) else { return nil }
            return try? JSONDecoder().decode(MasterSchedule.Actual.self, from: Data(XML.unescape(body).utf8))
        }

        /// Writes the record, replacing the one the file has, else adding the part with its properties, relationships
        /// and content type.
        static func write(_ actual: MasterSchedule.Actual, into zip: inout ZipArchive) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            guard let json = try? encoder.encode(actual) else { return }
            let item = #"<?xml version="1.0" encoding="UTF-8" standalone="no"?>"# + "\n"
                + #"<tc:progress xmlns:tc="\#(namespace)" version="1">"# + XML.escape(String(decoding: json, as: UTF8.self))
                + "</tc:progress>"
            if let path = part(zip) { zip.set(path, item); return }

            var n = 1
            while zip.contains("customXml/item\(n).xml") || zip.contains("customXml/itemProps\(n).xml") { n += 1 }
            zip.set("customXml/item\(n).xml", item)
            zip.set("customXml/itemProps\(n).xml", #"<?xml version="1.0" encoding="UTF-8" standalone="no"?>"# + "\n"
                + #"<ds:datastoreItem ds:itemID="{\#(UUID().uuidString)}" xmlns:ds="http://schemas.openxmlformats.org/officeDocument/2006/customXml">"#
                + #"<ds:schemaRefs><ds:schemaRef ds:uri="\#(namespace)"/></ds:schemaRefs></ds:datastoreItem>"#)
            zip.set("customXml/_rels/item\(n).xml.rels", #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
                + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
                + #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXmlProps" Target="itemProps\#(n).xml"/>"#
                + "</Relationships>")

            if var rels = zip.string("xl/_rels/workbook.xml.rels"), let end = rels.range(of: "</Relationships>") {
                // an id no other relationship has
                var id = relationshipID, k = 1
                while rels.contains(#"Id="\#(id)""#) { k += 1; id = relationshipID + String(k) }
                rels.insert(contentsOf: #"<Relationship Id="\#(id)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXml" Target="../customXml/item\#(n).xml"/>"#,
                            at: end.lowerBound)
                zip.set("xl/_rels/workbook.xml.rels", rels)
            }
            if var types = zip.string("[Content_Types].xml"), let end = types.range(of: "</Types>") {
                var add = #"<Override PartName="/customXml/itemProps\#(n).xml" ContentType="application/vnd.openxmlformats-officedocument.customXmlProperties+xml"/>"#
                if types.range(of: #"Extension="xml""#, options: .caseInsensitive) == nil {
                    add = #"<Default Extension="xml" ContentType="application/xml"/>"# + add
                }
                types.insert(contentsOf: add, at: end.lowerBound)
                zip.set("[Content_Types].xml", types)
            }
        }

        /// The custom XML part that holds the record.
        static func part(_ zip: ZipArchive) -> String? {
            zip.paths.first { p in
                p.hasPrefix("customXml/item") && p.hasSuffix(".xml") && !p.hasPrefix("customXml/itemProps")
                    && (zip.string(p)?.contains(namespace) ?? false)
            }
        }

        /// The text inside the part's root element, whatever prefix a save gave it.
        static func content(_ xml: String) -> String? {
            var at = xml.startIndex
            // past the declaration and any comments to the root's start tag
            while let lt = xml.range(of: "<", range: at..<xml.endIndex) {
                let next = xml.index(after: lt.lowerBound)
                guard next < xml.endIndex else { return nil }
                if xml[next] == "?" || xml[next] == "!" {
                    guard let gt = xml.range(of: ">", range: next..<xml.endIndex) else { return nil }
                    at = gt.upperBound
                    continue
                }
                guard let open = xml.range(of: ">", range: next..<xml.endIndex),
                      let close = xml.range(of: "</", options: .backwards, range: open.upperBound..<xml.endIndex) else { return nil }
                return String(xml[open.upperBound..<close.lowerBound])
            }
            return nil
        }
    }
}
