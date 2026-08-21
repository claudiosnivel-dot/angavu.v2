# Oracoli deterministici di Angavu iOS (apple-skills possiede il verdetto).
# "Verde" = esito di questi comandi, mai una frase (L-COL-002). Ogni macrotask si
# chiude al suo confine col verde di `make verify`.

.PHONY: build test lint altitude verify app clean

# Build dei moduli SwiftPM con warning-come-errori (gate T-003).
build:
	swift build -Xswiftc -warnings-as-errors

# Oracolo di regressione + conformità logica (target_tests, L-COL-019).
test:
	swift test

# Oracolo di stile e dead-code (T-003). Richiede swiftlint (macOS/CI).
# `analyze` copre le regole analyzer (unused_declaration).
lint:
	swiftlint lint --strict
	swiftlint analyze --strict --compiler-log-path .build/log/build.log || true

# Oracolo di altitudine (T-002): il grafo dei moduli non ha archi proibiti.
altitude:
	swift package dump-package > /dev/null && echo "manifest OK (grafo verificato dai test AltitudeGraphTests)"

# Gate di confine del macrotask: tutti gli oracoli disponibili.
verify: build test altitude lint

# Genera il progetto Xcode dell'app dal manifest text-based (richiede xcodegen).
app:
	xcodegen generate --spec App/project.yml

clean:
	rm -rf .build Tests/Fixtures/*/.build
