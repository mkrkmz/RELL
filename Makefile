PROJECT = Reader for Language Learner/Reader for Language Learner.xcodeproj
SCHEME = Reader for Language Learner
DESTINATION = platform=macOS
CONFIG = Debug
SIGNING = CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

.PHONY: build test clean lint format open

## Derleme
build:
	xcodebuild build \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination '$(DESTINATION)' \
		-configuration $(CONFIG) \
		$(SIGNING)

## Testleri calistir
test:
	xcodebuild test \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination '$(DESTINATION)' \
		-configuration $(CONFIG) \
		$(SIGNING)

## Release derleme
release:
	xcodebuild build \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination '$(DESTINATION)' \
		-configuration Release \
		$(SIGNING)

## Derleme artefaktlarini temizle
clean:
	xcodebuild clean \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-destination '$(DESTINATION)'
	rm -rf .DerivedData

## SwiftLint kontrolu (kurulum: brew install swiftlint)
lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --path "Reader for Language Learner/Reader for Language Learner"; \
	else \
		echo "SwiftLint bulunamadi. Kurulum: brew install swiftlint"; \
		exit 1; \
	fi

## SwiftLint otomatik duzeltme
fix:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --fix --path "Reader for Language Learner/Reader for Language Learner"; \
	else \
		echo "SwiftLint bulunamadi. Kurulum: brew install swiftlint"; \
		exit 1; \
	fi

## Swift dosyalarini formatla (swift-format gerektirir)
format:
	@if command -v swift-format >/dev/null 2>&1; then \
		find "Reader for Language Learner/Reader for Language Learner" -name "*.swift" -exec swift-format format -i {} +; \
	else \
		echo "swift-format bulunamadi. Kurulum: brew install swift-format"; \
		exit 1; \
	fi

## DMG olustur (lokal release)
dmg: release
	$(eval APP_PATH := $(shell find ~/Library/Developer/Xcode/DerivedData -path "*/Release/Reader for Language Learner.app" -type d 2>/dev/null | head -1))
	@if [ -z "$(APP_PATH)" ]; then echo "App bundle bulunamadi. Once 'make release' calistirin."; exit 1; fi
	@mkdir -p dmg_staging
	@cp -R "$(APP_PATH)" dmg_staging/
	@ln -sf /Applications dmg_staging/Applications
	hdiutil create -volname "RELL" -srcfolder dmg_staging -ov -format UDZO RELL-macOS.dmg
	@rm -rf dmg_staging
	@echo "DMG olusturuldu: RELL-macOS.dmg"

## Xcode projesini ac
open:
	open "$(PROJECT)"

## Yardim
help:
	@echo "Kullanilabilir komutlar:"
	@echo "  make build    - Debug derleme"
	@echo "  make test     - Testleri calistir"
	@echo "  make release  - Release derleme"
	@echo "  make dmg      - DMG olustur (release build + paketleme)"
	@echo "  make clean    - Derleme artefaktlarini temizle"
	@echo "  make lint     - SwiftLint kontrolu"
	@echo "  make fix      - SwiftLint otomatik duzeltme"
	@echo "  make format   - Swift dosyalarini formatla"
	@echo "  make open     - Xcode projesini ac"
