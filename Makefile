# cqlb — Makefile
# Wraps the build/install/run workflow for the cqlb menu bar app.

CONFIG       ?= debug
BUILD_FLAG   := -c $(CONFIG)
BUILD_DIR    := .build/$(CONFIG)
DIST_DIR     := dist
BUNDLE       := $(DIST_DIR)/cqlb.app
SETTINGS_BUNDLE := $(DIST_DIR)/cqlb Settings.app
IME_BUNDLE   := $(DIST_DIR)/cqlb-ime.app
INSTALL_DIR  := $(HOME)/Applications
IME_INSTALL_DIR := $(HOME)/Library/Input Methods
CERT_NAME    := cqlb-dev
# IMK bundles must be signed with an Apple Developer ID Application
# certificate (self-signed / ad-hoc signatures are silently filtered
# from the input-source picker on macOS 15+).
IME_CERT_NAME := Developer ID Application: CHUNHUI CAO (WW9TMJ499X)
# Notary profile name (created via `xcrun notarytool store-credentials`).
# On macOS 15+, Developer ID alone is not enough — IMEs additionally
# require a notarization ticket to be loadable by TextInputMenuAgent.
NOTARY_PROFILE := cqlb-notary
XCODE_DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
ifeq ($(origin DEVELOPER_DIR), undefined)
ifneq ($(wildcard $(XCODE_DEVELOPER_DIR)),)
export DEVELOPER_DIR := $(XCODE_DEVELOPER_DIR)
endif
endif
SWIFT        ?= xcrun swift
CLANG_MODULE_CACHE_PATH ?= $(CURDIR)/.build/module-cache
export CLANG_MODULE_CACHE_PATH

DICT_FILES   := cqlb.dict.yaml cqlb.src.dict.yaml ipinyin.dict.yaml \
                english.dict.yaml emoji_word.txt emoji_category.txt

.PHONY: build install run clean uninstall build-ime install-ime notarize-ime uninstall-ime

build:
	@echo "==> swift build ($(CONFIG))"
	@mkdir -p "$(CLANG_MODULE_CACHE_PATH)"
	$(SWIFT) build $(BUILD_FLAG) --product cqlb
	$(SWIFT) build $(BUILD_FLAG) --product cqlb-settings

install: build
	@echo "==> generating icon"
	@test -f Resources/cqlb.pdf || $(SWIFT) scripts/gen-icon.swift Resources/cqlb.pdf 两 2>/dev/null
	@echo "==> assembling $(BUNDLE)"
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(BUNDLE)/Contents/MacOS"
	@mkdir -p "$(BUNDLE)/Contents/Resources/Dicts"
	@cp "$(BUILD_DIR)/cqlb" "$(BUNDLE)/Contents/MacOS/cqlb"
	@cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	@cp Resources/cqlb.pdf "$(BUNDLE)/Contents/Resources/cqlb.pdf"
	@for f in $(DICT_FILES); do \
		if [ -f "Dicts/$$f" ]; then \
			cp "Dicts/$$f" "$(BUNDLE)/Contents/Resources/Dicts/$$f"; \
		fi; \
	done
	@xattr -cr "$(BUNDLE)" 2>/dev/null || true
	@echo "==> assembling $(SETTINGS_BUNDLE)"
	@rm -rf "$(SETTINGS_BUNDLE)"
	@mkdir -p "$(SETTINGS_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(SETTINGS_BUNDLE)/Contents/Resources"
	@cp "$(BUILD_DIR)/cqlb-settings" "$(SETTINGS_BUNDLE)/Contents/MacOS/cqlb-settings"
	@cp Resources/Settings-Info.plist "$(SETTINGS_BUNDLE)/Contents/Info.plist"
	@cp Resources/cqlb.pdf "$(SETTINGS_BUNDLE)/Contents/Resources/cqlb.pdf"
	@xattr -cr "$(SETTINGS_BUNDLE)" 2>/dev/null || true
	@echo "==> ensuring self-signed cert"
	@bash scripts/setup-cert.sh
	@echo "==> codesign with $(CERT_NAME)"
	@for bundle in "$(BUNDLE)" "$(SETTINGS_BUNDLE)"; do \
		codesign --force --deep --sign "$(CERT_NAME)" --options runtime "$$bundle" 2>&1 \
		|| { echo "codesign with $(CERT_NAME) failed for $$bundle, falling back to ad-hoc" >&2; \
		     codesign --force --deep --sign - "$$bundle" >/dev/null 2>&1; }; \
	done
	@mkdir -p "$(INSTALL_DIR)"
	@killall cqlb 2>/dev/null || true
	@killall cqlb-settings 2>/dev/null || true
	@rm -rf "$(INSTALL_DIR)/cqlb.app"
	@ditto "$(BUNDLE)" "$(INSTALL_DIR)/cqlb.app"
	@xattr -cr "$(INSTALL_DIR)/cqlb.app" 2>/dev/null || true
	@codesign --force --deep --sign "$(CERT_NAME)" --options runtime "$(INSTALL_DIR)/cqlb.app" 2>&1 \
		|| codesign --force --deep --sign - "$(INSTALL_DIR)/cqlb.app" >/dev/null 2>&1
	@rm -rf "$(INSTALL_DIR)/cqlb Settings.app"
	@ditto "$(SETTINGS_BUNDLE)" "$(INSTALL_DIR)/cqlb Settings.app"
	@xattr -cr "$(INSTALL_DIR)/cqlb Settings.app" 2>/dev/null || true
	@codesign --force --deep --sign "$(CERT_NAME)" --options runtime "$(INSTALL_DIR)/cqlb Settings.app" 2>&1 \
		|| codesign --force --deep --sign - "$(INSTALL_DIR)/cqlb Settings.app" >/dev/null 2>&1
	@echo ""
	@echo "cqlb installed to $(INSTALL_DIR)/cqlb.app"
	@echo "cqlb Settings installed to $(INSTALL_DIR)/cqlb Settings.app"

run: install
	@echo "==> launching cqlb"
	@open "$(INSTALL_DIR)/cqlb.app"

clean:
	@echo "==> cleaning"
	rm -rf .build $(DIST_DIR)

uninstall:
	@echo "==> uninstalling"
	@killall cqlb 2>/dev/null || true
	@killall cqlb-settings 2>/dev/null || true
	rm -rf "$(INSTALL_DIR)/cqlb.app" "$(INSTALL_DIR)/cqlb Settings.app"
	@echo "done"

# ----------------------------------------------------------------------
# IME target (InputMethodKit) — installs to ~/Library/Input Methods
# ----------------------------------------------------------------------

build-ime:
	@echo "==> swift build cqlb-ime ($(CONFIG))"
	@mkdir -p "$(CLANG_MODULE_CACHE_PATH)"
	$(SWIFT) build $(BUILD_FLAG) --product cqlb-ime

install-ime: build-ime
	@echo "==> generating icons"
	@# IME menu / picker icons use TIFF, matching Apple's built-in input
	@# methods. PDF stays for the standalone app + settings app.
	@bash scripts/gen-tiff.sh Resources/cqlb-label.tiff 两 2>/dev/null
	@bash scripts/gen-icns.sh Resources/cqlb.icns 两 >/dev/null
	@echo "==> assembling $(IME_BUNDLE)"
	@rm -rf "$(IME_BUNDLE)"
	@mkdir -p "$(IME_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(IME_BUNDLE)/Contents/Resources/Dicts"
	@cp "$(BUILD_DIR)/cqlb-ime" "$(IME_BUNDLE)/Contents/MacOS/cqlb-ime"
	@cp Resources/IME-Info.plist "$(IME_BUNDLE)/Contents/Info.plist"
	@# PkgInfo — 8-byte legacy file (package type + creator code). Some
	@# LaunchServices enumeration paths still probe this. Squirrel has it.
	@printf "APPL????" > "$(IME_BUNDLE)/Contents/PkgInfo"
	@cp Resources/cqlb-label.tiff "$(IME_BUNDLE)/Contents/Resources/cqlb-label.tiff"
	@cp Resources/cqlb.icns "$(IME_BUNDLE)/Contents/Resources/cqlb.icns"
	@# Localized names for the input-source picker. The picker picks
	@# CFBundleName/CFBundleDisplayName from the matching .lproj based on
	@# the current system language.
	@for lproj in en.lproj zh-Hans.lproj; do \
		if [ -d "Resources/$$lproj" ]; then \
			mkdir -p "$(IME_BUNDLE)/Contents/Resources/$$lproj"; \
			cp Resources/$$lproj/*.strings "$(IME_BUNDLE)/Contents/Resources/$$lproj/" 2>/dev/null || true; \
		fi; \
	done
	@for f in $(DICT_FILES); do \
		if [ -f "Dicts/$$f" ]; then \
			cp "Dicts/$$f" "$(IME_BUNDLE)/Contents/Resources/Dicts/$$f"; \
		fi; \
	done
	@xattr -cr "$(IME_BUNDLE)" 2>/dev/null || true
	@echo "==> codesign with Developer ID"
	@# IMEs must be signed with Developer ID — ad-hoc/self-signed bundles
	@# are silently filtered by TextInputMenuAgent on macOS 15+. We fail
	@# loudly here so the user isn't puzzled by a "successful" install
	@# that never shows up in the picker.
	@codesign --force --deep --sign "$(IME_CERT_NAME)" --options runtime \
		--timestamp "$(IME_BUNDLE)"
	@mkdir -p "$(IME_INSTALL_DIR)"
	@# The system launches the IME bundle on demand via TextInputMenuAgent.
	@# We have to kill the running instance before overwriting — the agent
	@# will relaunch the new version the next time we're the active IME.
	@killall cqlb-ime 2>/dev/null || true
	@rm -rf "$(IME_INSTALL_DIR)/cqlb-ime.app"
	@ditto "$(IME_BUNDLE)" "$(IME_INSTALL_DIR)/cqlb-ime.app"
	@xattr -cr "$(IME_INSTALL_DIR)/cqlb-ime.app" 2>/dev/null || true
	@codesign --force --deep --sign "$(IME_CERT_NAME)" --options runtime \
		--timestamp "$(IME_INSTALL_DIR)/cqlb-ime.app"
	@/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
		-f "$(IME_INSTALL_DIR)/cqlb-ime.app" >/dev/null
	@killall TextInputMenuAgent 2>/dev/null || true
	@echo ""
	@echo "cqlb IME installed to $(IME_INSTALL_DIR)/cqlb-ime.app"
	@echo ""
	@echo "First-time setup:"
	@echo "  1. Open System Settings → Keyboard → Text Input → Input Sources"
	@echo "  2. Click + → select 超强两笔"
	@echo "  3. Switch via Control+Space or the menu bar input switcher"
	@echo ""
	@echo "After code changes, just re-run 'make install-ime' — the system"
	@echo "will reload the new bundle on the next input mode switch."

notarize-ime:
	@# Submit the installed bundle to Apple's notary service and staple
	@# the resulting ticket back to it. Must be run AFTER install-ime.
	@# Takes 2–15 minutes typically; progress is streamed by notarytool.
	@test -d "$(IME_INSTALL_DIR)/cqlb-ime.app" \
		|| { echo "error: $(IME_INSTALL_DIR)/cqlb-ime.app not found — run 'make install-ime' first"; exit 1; }
	@echo "==> zipping bundle for submission"
	@rm -f "$(DIST_DIR)/cqlb-ime.zip"
	@ditto -c -k --keepParent "$(IME_INSTALL_DIR)/cqlb-ime.app" "$(DIST_DIR)/cqlb-ime.zip"
	@echo "==> submitting to Apple notary service (this can take a while)"
	@xcrun notarytool submit "$(DIST_DIR)/cqlb-ime.zip" \
		--keychain-profile "$(NOTARY_PROFILE)" \
		--wait
	@echo "==> stapling ticket to installed bundle"
	@xcrun stapler staple "$(IME_INSTALL_DIR)/cqlb-ime.app"
	@echo "==> verifying Gatekeeper acceptance"
	@spctl -a -vvv --type execute "$(IME_INSTALL_DIR)/cqlb-ime.app" || true
	@echo "==> refreshing LaunchServices"
	@/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
		-f "$(IME_INSTALL_DIR)/cqlb-ime.app" >/dev/null
	@killall TextInputMenuAgent 2>/dev/null || true
	@echo ""
	@echo "notarization complete. Open System Settings → Keyboard →"
	@echo "Text Input → Input Sources → + and look for 超强两笔."

uninstall-ime:
	@echo "==> uninstalling IME"
	@killall cqlb-ime 2>/dev/null || true
	rm -rf "$(IME_INSTALL_DIR)/cqlb-ime.app"
	@echo "done"
