# cqlb — Makefile
# Wraps the build/install/package workflow for the InputMethodKit IME.

CONFIG       ?= debug
BUILD_FLAG   = -c $(CONFIG)
BUILD_DIR    = .build/$(CONFIG)
DIST_DIR     := dist
IME_BUNDLE   := $(DIST_DIR)/cqlb-ime.app
IME_NOTARY_ZIP := $(DIST_DIR)/cqlb-ime-notary-submit.zip
IME_DIST_ZIP := $(DIST_DIR)/cqlb-ime-notarized.zip
PKG_ROOT     := $(DIST_DIR)/pkg-root
PKG_UNSIGNED := $(DIST_DIR)/cqlb-ime-unsigned.pkg
PKG_DIST     := $(DIST_DIR)/cqlb-ime-installer.pkg
PKG_COMPONENTS := scripts/pkg-components.plist
PKG_IDENTIFIER := com.cqlb.inputmethod.cqlb.pkg
PKG_VERSION  := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/IME-Info.plist 2>/dev/null || echo 0.1.0)
IME_ENTITLEMENTS := Resources/cqlb-ime.entitlements
IME_INSTALL_DIR := $(HOME)/Library/Input Methods
# IMK bundles must be signed with an Apple Developer ID Application
# certificate (self-signed / ad-hoc signatures are silently filtered
# from the input-source picker on macOS 15+).
IME_CERT_NAME := Developer ID Application: CHUNHUI CAO (WW9TMJ499X)
# Notary profile name (created via `xcrun notarytool store-credentials`).
# On macOS 15+, Developer ID alone is not enough — IMEs additionally
# require a notarization ticket to be loadable by TextInputMenuAgent.
NOTARY_PROFILE := cqlb-notary
# Optional. Set to a Developer ID Installer identity to produce a signed pkg:
#   make pkg-ime PKG_CERT_NAME="Developer ID Installer: Your Name (TEAMID)"
PKG_CERT_NAME ?=
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

.PHONY: build install clean uninstall build-ime install-ime notarize-ime package-ime pkg-ime package-installer uninstall-ime

build: build-ime

install: install-ime

uninstall: uninstall-ime

clean:
	@echo "==> cleaning"
	rm -rf .build $(DIST_DIR)

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
	@# methods. The app icon remains ICNS for Finder/LaunchServices paths.
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
		--entitlements "$(IME_ENTITLEMENTS)" \
		--timestamp "$(IME_BUNDLE)"
	@codesign --verify --strict --verbose=2 "$(IME_BUNDLE)"
	@mkdir -p "$(IME_INSTALL_DIR)"
	@# The system launches the IME bundle on demand via TextInputMenuAgent.
	@# We have to kill the running instance before overwriting — the agent
	@# will relaunch the new version the next time we're the active IME.
	@killall cqlb-ime 2>/dev/null || true
	@rm -rf "$(IME_INSTALL_DIR)/cqlb-ime.app"
	@ditto "$(IME_BUNDLE)" "$(IME_INSTALL_DIR)/cqlb-ime.app"
	@xattr -cr "$(IME_INSTALL_DIR)/cqlb-ime.app" 2>/dev/null || true
	@codesign --force --deep --sign "$(IME_CERT_NAME)" --options runtime \
		--entitlements "$(IME_ENTITLEMENTS)" \
		--timestamp "$(IME_INSTALL_DIR)/cqlb-ime.app"
	@codesign --verify --strict --verbose=2 "$(IME_INSTALL_DIR)/cqlb-ime.app"
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
	@echo "Settings are available from the input switcher menu while cqlb is active."

notarize-ime:
	@# Submit the installed bundle to Apple's notary service and staple
	@# the resulting ticket back to it. Must be run AFTER install-ime.
	@# Takes 2–15 minutes typically; progress is streamed by notarytool.
	@test -d "$(IME_INSTALL_DIR)/cqlb-ime.app" \
		|| { echo "error: $(IME_INSTALL_DIR)/cqlb-ime.app not found — run 'make install-ime' first"; exit 1; }
	@echo "==> zipping bundle for submission"
	@rm -f "$(IME_NOTARY_ZIP)" "$(IME_DIST_ZIP)"
	@ditto -c -k --keepParent "$(IME_INSTALL_DIR)/cqlb-ime.app" "$(IME_NOTARY_ZIP)"
	@echo "==> submitting to Apple notary service (this can take a while)"
	@xcrun notarytool submit "$(IME_NOTARY_ZIP)" \
		--keychain-profile "$(NOTARY_PROFILE)" \
		--wait
	@echo "==> stapling ticket to installed bundle"
	@xcrun stapler staple "$(IME_INSTALL_DIR)/cqlb-ime.app"
	@echo "==> validating stapled notarization ticket"
	@xcrun stapler validate "$(IME_INSTALL_DIR)/cqlb-ime.app"
	@codesign --verify --strict --verbose=2 -R="notarized" "$(IME_INSTALL_DIR)/cqlb-ime.app"
	@echo "==> refreshing LaunchServices"
	@/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
		-f "$(IME_INSTALL_DIR)/cqlb-ime.app" >/dev/null
	@killall TextInputMenuAgent 2>/dev/null || true
	@echo "==> creating distributable zip"
	@ditto -c -k --keepParent "$(IME_INSTALL_DIR)/cqlb-ime.app" "$(IME_DIST_ZIP)"
	@echo ""
	@echo "notarization complete. Distributable archive:"
	@echo "  $(IME_DIST_ZIP)"
	@echo ""
	@echo "Open System Settings → Keyboard →"
	@echo "Text Input → Input Sources → + and look for 超强两笔."

package-ime:
	@$(MAKE) CONFIG=release install-ime
	@$(MAKE) CONFIG=release notarize-ime

pkg-ime:
	@test -d "$(IME_INSTALL_DIR)/cqlb-ime.app" \
		|| { echo "error: $(IME_INSTALL_DIR)/cqlb-ime.app not found — run 'make package-ime' first"; exit 1; }
	@echo "==> validating installed IME before packaging"
	@xcrun stapler validate "$(IME_INSTALL_DIR)/cqlb-ime.app"
	@codesign --verify --strict --verbose=2 -R="notarized" "$(IME_INSTALL_DIR)/cqlb-ime.app"
	@echo "==> staging pkg payload"
	@rm -rf "$(PKG_ROOT)" "$(PKG_UNSIGNED)" "$(PKG_DIST)"
	@mkdir -p "$(PKG_ROOT)/Library/Input Methods"
	@COPYFILE_DISABLE=1 ditto --norsrc --noextattr --noqtn \
		"$(IME_INSTALL_DIR)/cqlb-ime.app" \
		"$(PKG_ROOT)/Library/Input Methods/cqlb-ime.app"
	@find "$(PKG_ROOT)" -name ".DS_Store" -delete
	@xattr -cr "$(PKG_ROOT)" 2>/dev/null || true
	@echo "==> building pkg"
	@COPYFILE_DISABLE=1 pkgbuild \
		--root "$(PKG_ROOT)" \
		--component-plist "$(PKG_COMPONENTS)" \
		--scripts scripts/pkg \
		--identifier "$(PKG_IDENTIFIER)" \
		--version "$(PKG_VERSION)" \
		--install-location / \
		"$(PKG_UNSIGNED)"
	@if [ -n "$(PKG_CERT_NAME)" ]; then \
		echo "==> signing pkg with $(PKG_CERT_NAME)"; \
		productsign --sign "$(PKG_CERT_NAME)" "$(PKG_UNSIGNED)" "$(PKG_DIST)"; \
	else \
		echo "==> no PKG_CERT_NAME set; leaving pkg unsigned"; \
		cp "$(PKG_UNSIGNED)" "$(PKG_DIST)"; \
	fi
	@pkgutil --check-signature "$(PKG_DIST)" || true
	@echo ""
	@echo "installer package ready:"
	@echo "  $(PKG_DIST)"

package-installer: package-ime pkg-ime

uninstall-ime:
	@echo "==> uninstalling IME"
	@killall cqlb-ime 2>/dev/null || true
	rm -rf "$(IME_INSTALL_DIR)/cqlb-ime.app"
	@echo "done"
