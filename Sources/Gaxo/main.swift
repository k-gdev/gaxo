import AppKit

// Build helper: `Gaxo --write-iconset <dir>` writes the app icon and exits.
if let flag = CommandLine.arguments.firstIndex(of: "--write-iconset"), flag + 1 < CommandLine.arguments.count {
    do {
        try IconExport.writeIconset(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("could not write iconset: \(error)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
