# cqlb — Makefile
# Wraps the build/install/run workflow for the cqlb menu bar app.

CONFIG       ?= debug
BUILD_FLAG   := -c $(CONFIG)
BUILD_DIR    := .build/$(CONFIG)
DIST_DIR     := dist
BUNDLE       := $(DIST_DIR)/cqlb.app
SETTINGS_BUNDLE := $(DIST_DIR)/cqlb Settings.app
INSTALL_DIR  := $(HOME)/Applications
CERT_NAME    := cqlb-dev

DICT_FILES   := cqlb.dict.yaml cqlb.src.dict.yaml ipinyin.dict.yaml \
                english.dict.yaml emoji_word.txt emoji_category.txt

.PHONY: build install run clean uninstall

build:
	@echo "==> swift build ($(CONFIG))"
	swift build $(BUILD_FLAG) --product cqlb
	swift build $(BUILD_FLAG) --product cqlb-settings

install: build
	@echo "==> generating icon"
	@test -f Resources/cqlb.pdf || swift scripts/gen-icon.swift Resources/cqlb.pdf 两 2>/dev/null
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
