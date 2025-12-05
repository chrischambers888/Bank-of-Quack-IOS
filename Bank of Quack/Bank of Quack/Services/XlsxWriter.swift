import Foundation
import ZIPFoundation

/// Progress callback for export operations
/// - Parameters:
///   - phase: Description of current phase (e.g., "Building strings", "Writing sheet 1")
///   - progress: Progress value from 0.0 to 1.0
typealias ExportProgressCallback = @Sendable (_ phase: String, _ progress: Double) -> Void

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
    /// - Parameters:
    ///   - filename: The output filename
    ///   - progressCallback: Optional callback for progress updates
    func write(to filename: String, progressCallback: ExportProgressCallback? = nil) throws -> URL {
        // Build shared strings table first
        progressCallback?("Preparing data...", 0.05)
        buildSharedStrings()
        
        let tempDir = FileManager.default.temporaryDirectory
        let xlsxURL = tempDir.appendingPathComponent(filename)
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: xlsxURL)
        
        // Create archive directly by adding data entries
        let archive = try Archive(url: xlsxURL, accessMode: .create)
        
        progressCallback?("Creating workbook structure...", 0.1)
        
        // Add all required files directly to the archive
        try addFileToArchive(archive, path: "[Content_Types].xml", content: generateContentTypes())
        try addFileToArchive(archive, path: "_rels/.rels", content: generateRootRels())
        try addFileToArchive(archive, path: "xl/_rels/workbook.xml.rels", content: generateWorkbookRels())
        try addFileToArchive(archive, path: "xl/workbook.xml", content: generateWorkbook())
        try addFileToArchive(archive, path: "xl/styles.xml", content: generateStyles())
        
        progressCallback?("Writing shared strings...", 0.15)
        try addFileToArchive(archive, path: "xl/sharedStrings.xml", content: generateSharedStrings())
        
        // Add each worksheet - this is typically the bulk of the work
        let sheetProgressStart = 0.2
        let sheetProgressEnd = 0.95
        let sheetProgressRange = sheetProgressEnd - sheetProgressStart
        
        for (index, sheet) in sheets.enumerated() {
            let sheetProgress = sheetProgressStart + (Double(index) / Double(sheets.count)) * sheetProgressRange
            progressCallback?("Writing \(sheet.name)...", sheetProgress)
            
            let content = generateWorksheet(sheet, index: index + 1)
            try addFileToArchive(archive, path: "xl/worksheets/sheet\(index + 1).xml", content: content)
        }
        
        progressCallback?("Finalizing export...", 0.98)
        
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
        // Use array + joined() for efficient string building
        let sheetOverrides = sheets.enumerated().map { index, _ in
            "<Override PartName=\"/xl/worksheets/sheet\(index + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }.joined()
        
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
        // Build relationships array efficiently
        var relationshipParts: [String] = sheets.enumerated().map { index, _ in
            "<Relationship Id=\"rId\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(index + 1).xml\"/>"
        }
        
        let stylesId = sheets.count + 1
        let stringsId = sheets.count + 2
        
        relationshipParts.append("<Relationship Id=\"rId\(stylesId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>")
        relationshipParts.append("<Relationship Id=\"rId\(stringsId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/>")
        
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(relationshipParts.joined())</Relationships>
        """
    }
    
    private func generateWorkbook() -> String {
        let sheetElements = sheets.enumerated().map { index, sheet in
            let escapedName = escapeXML(sheet.name)
            return "<sheet name=\"\(escapedName)\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
        }.joined()
        
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
        // Use map + joined for O(n) instead of O(n²) string building
        let stringElements = sharedStrings.map { string in
            let escapedString = escapeXML(string)
            return "<si><t>\(escapedString)</t></si>"
        }.joined()
        
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(sharedStrings.count)" uniqueCount="\(sharedStrings.count)">\(stringElements)</sst>
        """
    }
    
    private func generateWorksheet(_ sheet: Sheet, index: Int) -> String {
        // Pre-compute column letters to avoid repeated calculations
        let maxCols = max(sheet.headers.count, sheet.rows.map { $0.count }.max() ?? 0)
        let columnLetters = (0..<maxCols).map { columnLetter(for: $0) }
        
        // Build rows array efficiently using map + joined
        var rowParts: [String] = []
        rowParts.reserveCapacity(sheet.rows.count + 1)
        
        // Header row (row 1) - use map for cells
        let headerCells = sheet.headers.enumerated().map { colIndex, header in
            let colLetter = colIndex < columnLetters.count ? columnLetters[colIndex] : columnLetter(for: colIndex)
            let stringIndex = getStringIndex(header)
            return "<c r=\"\(colLetter)1\" t=\"s\" s=\"1\"><v>\(stringIndex)</v></c>"
        }.joined()
        rowParts.append("<row r=\"1\">\(headerCells)</row>")
        
        // Data rows - use map for both rows and cells
        let dataRows = sheet.rows.enumerated().map { rowIndex, row -> String in
            let excelRow = rowIndex + 2
            let cells = row.enumerated().map { colIndex, cellValue -> String in
                let colLetter = colIndex < columnLetters.count ? columnLetters[colIndex] : columnLetter(for: colIndex)
                let stringIndex = getStringIndex(cellValue)
                return "<c r=\"\(colLetter)\(excelRow)\" t=\"s\"><v>\(stringIndex)</v></c>"
            }.joined()
            return "<row r=\"\(excelRow)\">\(cells)</row>"
        }
        rowParts.append(contentsOf: dataRows)
        
        let rowElements = rowParts.joined()
        
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
