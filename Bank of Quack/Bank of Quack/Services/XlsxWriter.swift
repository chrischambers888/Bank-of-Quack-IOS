import Foundation
import ZIPFoundation

/// A helper class to create XLSX files from tabular data
/// XLSX files are essentially ZIP archives containing XML files
final class XlsxWriter {
    
    // MARK: - Types
    
    struct Sheet {
        let name: String
        let headers: [String]
        let rows: [[String]]
    }
    
    // MARK: - Properties
    
    private var sheets: [Sheet] = []
    private var sharedStrings: [String] = []
    private var stringIndexMap: [String: Int] = [:]
    
    // MARK: - Public Methods
    
    /// Adds a sheet to the workbook
    func addSheet(name: String, headers: [String], rows: [[String]]) {
        sheets.append(Sheet(name: name, headers: headers, rows: rows))
    }
    
    /// Writes the workbook to a file and returns the URL
    func write(to filename: String) throws -> URL {
        // Build shared strings table first
        buildSharedStrings()
        
        let tempDir = FileManager.default.temporaryDirectory
        let xlsxURL = tempDir.appendingPathComponent(filename)
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: xlsxURL)
        
        // Create archive directly by adding data entries
        let archive = try Archive(url: xlsxURL, accessMode: .create)
        
        // Add all required files directly to the archive
        try addFileToArchive(archive, path: "[Content_Types].xml", content: generateContentTypes())
        try addFileToArchive(archive, path: "_rels/.rels", content: generateRootRels())
        try addFileToArchive(archive, path: "xl/_rels/workbook.xml.rels", content: generateWorkbookRels())
        try addFileToArchive(archive, path: "xl/workbook.xml", content: generateWorkbook())
        try addFileToArchive(archive, path: "xl/styles.xml", content: generateStyles())
        try addFileToArchive(archive, path: "xl/sharedStrings.xml", content: generateSharedStrings())
        
        // Add each worksheet
        for (index, sheet) in sheets.enumerated() {
            let content = generateWorksheet(sheet, index: index + 1)
            try addFileToArchive(archive, path: "xl/worksheets/sheet\(index + 1).xml", content: content)
        }
        
        return xlsxURL
    }
    
    // MARK: - Archive Helper
    
    private func addFileToArchive(_ archive: Archive, path: String, content: String) throws {
        guard let data = content.data(using: .utf8) else {
            throw XlsxWriterError.failedToCreateArchive
        }
        
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            provider: { position, size in
                let start = Int(position)
                let end = min(start + size, data.count)
                return data.subdata(in: start..<end)
            }
        )
    }
    
    // MARK: - Private Methods
    
    private func buildSharedStrings() {
        sharedStrings = []
        stringIndexMap = [:]
        
        for sheet in sheets {
            for header in sheet.headers {
                addToSharedStrings(header)
            }
            for row in sheet.rows {
                for cell in row {
                    addToSharedStrings(cell)
                }
            }
        }
    }
    
    private func addToSharedStrings(_ string: String) {
        if stringIndexMap[string] == nil {
            stringIndexMap[string] = sharedStrings.count
            sharedStrings.append(string)
        }
    }
    
    private func getStringIndex(_ string: String) -> Int {
        return stringIndexMap[string] ?? 0
    }
    
    private func generateContentTypes() -> String {
        var sheetOverrides = ""
        for (index, _) in sheets.enumerated() {
            sheetOverrides += "<Override PartName=\"/xl/worksheets/sheet\(index + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>\(sheetOverrides)</Types>
        """
    }
    
    private func generateRootRels() -> String {
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """
    }
    
    private func generateWorkbookRels() -> String {
        var relationships = ""
        for (index, _) in sheets.enumerated() {
            relationships += "<Relationship Id=\"rId\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(index + 1).xml\"/>"
        }
        
        let stylesId = sheets.count + 1
        let stringsId = sheets.count + 2
        
        relationships += "<Relationship Id=\"rId\(stylesId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        relationships += "<Relationship Id=\"rId\(stringsId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/>"
        
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(relationships)</Relationships>
        """
    }
    
    private func generateWorkbook() -> String {
        var sheetElements = ""
        for (index, sheet) in sheets.enumerated() {
            let escapedName = escapeXML(sheet.name)
            sheetElements += "<sheet name=\"\(escapedName)\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
        }
        
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(sheetElements)</sheets></workbook>
        """
    }
    
    private func generateStyles() -> String {
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font><font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
        """
    }
    
    private func generateSharedStrings() -> String {
        var stringElements = ""
        for string in sharedStrings {
            let escapedString = escapeXML(string)
            stringElements += "<si><t>\(escapedString)</t></si>"
        }
        
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(sharedStrings.count)" uniqueCount="\(sharedStrings.count)">\(stringElements)</sst>
        """
    }
    
    private func generateWorksheet(_ sheet: Sheet, index: Int) -> String {
        var rowElements = ""
        
        // Header row (row 1)
        var headerCells = ""
        for (colIndex, header) in sheet.headers.enumerated() {
            let colLetter = columnLetter(for: colIndex)
            let stringIndex = getStringIndex(header)
            headerCells += "<c r=\"\(colLetter)1\" t=\"s\" s=\"1\"><v>\(stringIndex)</v></c>"
        }
        rowElements += "<row r=\"1\">\(headerCells)</row>"
        
        // Data rows
        for (rowIndex, row) in sheet.rows.enumerated() {
            let excelRow = rowIndex + 2
            var cells = ""
            for (colIndex, cellValue) in row.enumerated() {
                let colLetter = columnLetter(for: colIndex)
                let stringIndex = getStringIndex(cellValue)
                cells += "<c r=\"\(colLetter)\(excelRow)\" t=\"s\"><v>\(stringIndex)</v></c>"
            }
            rowElements += "<row r=\"\(excelRow)\">\(cells)</row>"
        }
        
        // Calculate the dimension
        let lastCol = columnLetter(for: max(sheet.headers.count - 1, 0))
        let lastRow = sheet.rows.count + 1
        
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:\(lastCol)\(lastRow)"/><sheetViews><sheetView workbookViewId="0"\(index == 1 ? " tabSelected=\"1\"" : "")/></sheetViews><sheetFormatPr defaultRowHeight="15"/><sheetData>\(rowElements)</sheetData></worksheet>
        """
    }
    
    private func columnLetter(for index: Int) -> String {
        var result = ""
        var n = index
        
        repeat {
            result = String(UnicodeScalar(65 + (n % 26))!) + result
            n = n / 26 - 1
        } while n >= 0
        
        return result
    }
    
    private func escapeXML(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        // Remove control characters that are invalid in XML
        result = result.filter { char in
            guard let scalar = char.unicodeScalars.first else { return false }
            return scalar.value >= 32 || scalar.value == 9 || scalar.value == 10 || scalar.value == 13
        }
        return result
    }
}

// MARK: - Errors

enum XlsxWriterError: LocalizedError {
    case failedToCreateArchive
    case failedToEnumerateFiles
    
    var errorDescription: String? {
        switch self {
        case .failedToCreateArchive:
            return "Failed to create XLSX archive"
        case .failedToEnumerateFiles:
            return "Failed to enumerate files for archive"
        }
    }
}
