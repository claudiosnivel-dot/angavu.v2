import Foundation

/// Esecutore di comandi deterministico per gli oracoli di fondazione.
/// Su piattaforme senza Process (nessuna sull'attuale toolchain) i chiamanti
/// gestiscono l'assenza via XCTSkip — mai un verde finto (L-COL-006).
enum Shell {
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Esegue `swift <args>` in `directory`. Restituisce nil se `swift` non è
    /// risolvibile nell'ambiente (oracolo dichiarato non coperto qui).
    /// `isolatedHome`: se true, forza HOME su una cartella temporanea unica così
    /// da NON contendere il lock del manifest-cache SwiftPM con il `swift test`
    /// esterno (evita il deadlock quando si ispeziona lo stesso package).
    static func swift(_ args: [String], in directory: URL, isolatedHome: Bool = false) -> Result? {
        run(executable: "swift", args: args, in: directory, isolatedHome: isolatedHome)
    }

    static func run(
        executable: String,
        args: [String],
        in directory: URL,
        isolatedHome: Bool = false
    ) -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + args
        process.currentDirectoryURL = directory

        if isolatedHome {
            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.temporaryDirectory
                .appendingPathComponent("angavu-nested-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            env["HOME"] = home.path
            process.environment = env
        }

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return nil
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
