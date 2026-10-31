APP_NAME = RokuRemote
SOURCE = RokuRemoteGUI.swift
BUILD_DIR = .build_output
USER_APPS = $(HOME)/Applications

all: bundle

# 1. Compile the Swift script as a library binary
compile:
	@echo "Compiling Swift script..."
	@mkdir -p $(BUILD_DIR)
	swiftc -parse-as-library $(SOURCE) -o $(BUILD_DIR)/$(APP_NAME)

# 2. Build the native macOS .app bundle structure locally
bundle: compile
	@echo "Creating macOS .app bundle locally..."
	@rm -rf $(APP_NAME).app
	@mkdir -p $(APP_NAME).app/Contents/MacOS
	@mkdir -p $(APP_NAME).app/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_NAME).app/Contents/MacOS/$(APP_NAME)
	
	# Generate Info.plist with local network permissions
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > $(APP_NAME).app/Contents/Info.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(APP_NAME).app/Contents/Info.plist
	@echo '<plist version="1.0"><dict>' >> $(APP_NAME).app/Contents/Info.plist
	@echo '    <key>CFBundleExecutable</key><string>$(APP_NAME)</string>' >> $(APP_NAME).app/Contents/Info.plist
	@echo '    <key>CFBundleIdentifier</key><string>com.local.$(APP_NAME)</string>' >> $(APP_NAME).app/Contents/Info.plist
	@echo '    <key>CFBundleName</key><string>$(APP_NAME)</string>' >> $(APP_NAME).app/Contents/Info.plist
	@echo '    <key>CFBundlePackageType</key><string>APPL</string>' >> $(APP_NAME).app/Contents/Info.plist
	@echo '    <key>CFBundleShortVersionString</key><string>1.0</string>' >> $(APP_NAME).app/Contents/Info.plist
	@echo '    <key>LSUIElement</key><false/>' >> $(APP_NAME).app/Contents/Info.plist
	@echo '    <key>NSLocalNetworkUsageDescription</key><string>RokuRemote needs local network access to discover and control your Roku device.</string>' >> $(APP_NAME).app/Contents/Info.plist
	@echo '</dict></plist>' >> $(APP_NAME).app/Contents/Info.plist
	@echo "✅ Successfully built $(APP_NAME).app locally."

# 3. Install globally to /Applications (requires admin privileges)
install: bundle
	@echo "Installing to /Applications..."
	@sudo rm -rf /Applications/$(APP_NAME).app
	@sudo cp -r $(APP_NAME).app /Applications/
	@echo "🚀 Installed successfully to /Applications/$(APP_NAME).app"

# 4. Install locally to ~/Applications/ (No sudo required)
local: bundle
	@echo "Installing to user Applications (~/Applications)..."
	@mkdir -p $(USER_APPS)
	@rm -rf $(USER_APPS)/$(APP_NAME).app
	@cp -r $(APP_NAME).app $(USER_APPS)/
	@echo "✨ Successfully installed to ~/Applications/$(APP_NAME).app"

# 5. Clean up temporary build artifacts
clean:
	@rm -rf $(BUILD_DIR) $(APP_NAME).app
	@echo "Cleaned local build artifacts."

.PHONY: all compile bundle install local clean
