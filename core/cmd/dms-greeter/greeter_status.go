package main

import (
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"

	"github.com/AvengeMedia/dank-greeter/core/internal/distros"
	"github.com/AvengeMedia/dank-greeter/core/internal/greeter"
	sharedpam "github.com/AvengeMedia/dank-greeter/core/internal/pam"
	"github.com/AvengeMedia/dank-greeter/core/internal/utils"
)

func isGreeterEnabled() bool {
	command := readDefaultSessionCommand("/etc/greetd/config.toml")
	return command != "" && strings.Contains(command, "dms-greeter")
}

func detectConfiguredCompositor() string {
	command := strings.ToLower(readDefaultSessionCommand("/etc/greetd/config.toml"))
	switch {
	case strings.Contains(command, "--command niri"):
		return "niri"
	case strings.Contains(command, "--command hyprland"):
		return "hyprland"
	case strings.Contains(command, "--command sway"):
		return "sway"
	}
	return ""
}

func stripTomlComment(line string) string {
	trimmed := strings.TrimSpace(line)
	if idx := strings.Index(trimmed, "#"); idx >= 0 {
		return strings.TrimSpace(trimmed[:idx])
	}
	return trimmed
}

func parseTomlSection(line string) (string, bool) {
	trimmed := stripTomlComment(line)
	if len(trimmed) < 3 || !strings.HasPrefix(trimmed, "[") || !strings.HasSuffix(trimmed, "]") {
		return "", false
	}
	return strings.TrimSpace(trimmed[1 : len(trimmed)-1]), true
}

func readDefaultSessionCommand(configPath string) string {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return ""
	}

	inDefaultSession := false
	for line := range strings.SplitSeq(string(data), "\n") {
		if section, ok := parseTomlSection(line); ok {
			inDefaultSession = section == "default_session"
			continue
		}

		if !inDefaultSession {
			continue
		}

		trimmed := stripTomlComment(line)
		if !strings.HasPrefix(trimmed, "command =") && !strings.HasPrefix(trimmed, "command=") {
			continue
		}

		parts := strings.SplitN(trimmed, "=", 2)
		if len(parts) != 2 {
			continue
		}

		command := strings.Trim(strings.TrimSpace(parts[1]), `"`)
		if command != "" {
			return command
		}
	}

	return ""
}

func explicitGreeterCacheDirFromCommand(command string) (string, bool) {
	tokens := strings.Fields(command)
	for i := 0; i < len(tokens); i++ {
		token := strings.Trim(tokens[i], "\"")
		if token == "--cache-dir" && i+1 < len(tokens) {
			value := strings.Trim(tokens[i+1], "\"")
			if value != "" {
				return value, true
			}
		}
		if strings.HasPrefix(token, "--cache-dir=") {
			value := strings.TrimPrefix(token, "--cache-dir=")
			value = strings.Trim(value, "\"")
			if value != "" {
				return value, true
			}
		}
	}
	return "", false
}

const nixOSGreeterStateDir = "/var/lib/dms-greeter"

func greeterStatusStateDir(command string, isNixOS bool) string {
	if cacheDir, ok := explicitGreeterCacheDirFromCommand(command); ok {
		return cacheDir
	}
	if isNixOS {
		return nixOSGreeterStateDir
	}
	return greeter.GreeterCacheDir
}

func extractGreeterWrapperFromCommand(command string) string {
	if command == "" {
		return ""
	}
	tokens := strings.Fields(command)
	if len(tokens) == 0 {
		return ""
	}
	wrapperIndex := 0
	if filepath.Base(strings.Trim(tokens[0], "\"")) == "env" {
		wrapperIndex = 1
		for wrapperIndex < len(tokens) && strings.Contains(tokens[wrapperIndex], "=") {
			wrapperIndex++
		}
	}
	if wrapperIndex >= len(tokens) {
		return ""
	}

	wrapper := strings.Trim(tokens[wrapperIndex], "\"")
	if wrapper == "" {
		return ""
	}
	if wrapperIndex+1 < len(tokens) {
		next := strings.Trim(tokens[wrapperIndex+1], "\"")
		if next != "" && (filepath.Base(wrapper) == "bash" || filepath.Base(wrapper) == "sh") && strings.Contains(filepath.Base(next), "dms-greeter") {
			return fmt.Sprintf("%s (script: %s)", wrapper, next)
		}
	}
	return wrapper
}

// extractGreeterShellDirFromCommand returns a shell-dir override from the
// configured greetd command: -c/--shell-dir, or the legacy -p/--path used by
// the wrapper-based install.
func extractGreeterShellDirFromCommand(command string) string {
	if command == "" {
		return ""
	}
	tokens := strings.Fields(command)
	for i := 0; i < len(tokens); i++ {
		token := strings.Trim(tokens[i], "\"")
		switch {
		case (token == "-c" || token == "--shell-dir" || token == "-p" || token == "--path") && i+1 < len(tokens):
			return strings.Trim(tokens[i+1], "\"")
		case strings.HasPrefix(token, "--shell-dir="):
			if value := strings.Trim(strings.TrimPrefix(token, "--shell-dir="), "\""); value != "" {
				return value
			}
		case strings.HasPrefix(token, "--path="):
			if value := strings.Trim(strings.TrimPrefix(token, "--path="), "\""); value != "" {
				return value
			}
		}
	}
	return ""
}

func installHint() string {
	return "Run 'dms-greeter install' to set up the greeter"
}

func systemPamManagerRemediationHint() string {
	const genericHint = "Disable it in your PAM manager (authselect/pam-auth-update) or in the included PAM stack to force password-only greeter login."

	osInfo, err := distros.GetOSInfo()
	if err != nil {
		return genericHint
	}
	config, exists := distros.Registry[osInfo.Distribution.ID]
	if !exists {
		return genericHint
	}

	switch config.Family {
	case distros.FamilyFedora:
		return "Disable it in authselect to force password-only greeter login."
	case distros.FamilyDebian, distros.FamilyUbuntu:
		return "Disable it in pam-auth-update to force password-only greeter login."
	default:
		return "Disable it in your distro PAM manager (authselect/pam-auth-update) or in the included PAM stack to force password-only greeter login."
	}
}

func checkGreeterStatus() error {
	fmt.Println("=== DMS Greeter Status ===")
	fmt.Println()

	if greeterIsNixOSFn() {
		return checkNixOSGreeterStatus()
	}

	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("failed to get user home directory: %w", err)
	}

	currentUser, err := user.Current()
	if err != nil {
		return fmt.Errorf("failed to get current user: %w", err)
	}

	configPath := "/etc/greetd/config.toml"
	configuredCommand := ""
	allGood := true
	fmt.Println("Greeter Configuration:")
	if _, err := os.ReadFile(configPath); err == nil {
		configuredCommand = readDefaultSessionCommand(configPath)
		if configuredCommand != "" && strings.Contains(configuredCommand, "dms-greeter") {
			fmt.Println("  ✓ Greeter is enabled")
			if wrapper := extractGreeterWrapperFromCommand(configuredCommand); wrapper != "" {
				fmt.Printf("  Command: %s\n", wrapper)
			}
			if shellDir := extractGreeterShellDirFromCommand(configuredCommand); shellDir != "" {
				fmt.Printf("  UI path override: %s\n", shellDir)
			}

			compositor := detectConfiguredCompositor()
			switch compositor {
			case "niri":
				fmt.Println("  Compositor: niri")
			case "hyprland":
				fmt.Println("  Compositor: Hyprland")
			case "sway":
				fmt.Println("  Compositor: sway")
			default:
				fmt.Println("  Compositor: unknown")
			}
		} else {
			fmt.Println("  ✗ Greeter is NOT enabled")
			fmt.Println("    Run 'dms-greeter enable' to enable it, or use the Activate button in Settings → Greeter, then Sync.")
			allGood = false
		}
	} else {
		fmt.Println("  ✗ Greeter config not found")
		fmt.Printf("    %s\n", installHint())
		allGood = false
	}

	if legacyPaths := greeter.LegacyWrapperScriptPaths(); len(legacyPaths) > 0 {
		fmt.Printf("  ⚠ Legacy dms-greeter shell wrapper detected at %s\n", strings.Join(legacyPaths, ", "))
		fmt.Println("    Remove it (or the old dms-greeter package) so the standalone binary is used.")
		allGood = false
	}

	fmt.Println("\nGroup Membership:")
	groupsCmd := exec.Command("groups", currentUser.Username)
	groupsOutput, err := groupsCmd.Output()
	if err != nil {
		return fmt.Errorf("failed to check groups: %w", err)
	}

	greeterGroup := greeter.DetectGreeterGroup()
	inGreeterGroup := strings.Contains(string(groupsOutput), greeterGroup)
	if inGreeterGroup {
		fmt.Printf("  ✓ User is in %s group\n", greeterGroup)
	} else {
		fmt.Printf("  ✗ User is NOT in %s group\n", greeterGroup)
		fmt.Println("    Run 'dms-greeter sync' to set up group membership and permissions")
	}

	cacheDir := greeterStatusStateDir(configuredCommand, false)
	fmt.Println("\nGreeter Cache Directory:")
	fmt.Printf("  Effective cache dir: %s\n", cacheDir)
	if cacheDir != greeter.GreeterCacheDir {
		fmt.Printf("  ⚠ Non-default cache dir detected (default: %s)\n", greeter.GreeterCacheDir)
	}
	if stat, err := os.Stat(cacheDir); err == nil && stat.IsDir() {
		fmt.Printf("  ✓ %s exists\n", cacheDir)
		requiredSubdirs := []string{".local/state", ".local/share", ".cache"}
		missingSubdirs := false
		for _, sub := range requiredSubdirs {
			subPath := filepath.Join(cacheDir, sub)
			if _, err := os.Stat(subPath); os.IsNotExist(err) {
				fmt.Printf("  ⚠ Missing required subdir: %s\n", subPath)
				missingSubdirs = true
			}
		}
		if missingSubdirs {
			fmt.Println("    Run 'dms-greeter sync' to initialize the cache directory structure.")
			allGood = false
		}
	} else {
		fmt.Printf("  ✗ %s not found\n", cacheDir)
		fmt.Printf("    %s\n", installHint())
		return nil
	}

	fmt.Println("\nConfiguration Symlinks:")
	colorSyncInfo, colorSyncErr := greeter.ResolveGreeterColorSyncInfo(homeDir)
	if colorSyncErr != nil {
		fmt.Printf("  ✗ Failed to resolve expected greeter color source: %v\n", colorSyncErr)
		allGood = false
		colorSyncInfo = greeter.GreeterColorSyncInfo{
			SourcePath: filepath.Join(homeDir, ".cache", "DankMaterialShell", "dms-colors.json"),
		}
	}

	colorThemeDesc := "Color theme"
	if colorSyncInfo.UsesDynamicWallpaperOverride {
		colorThemeDesc = "Color theme (greeter wallpaper override)"
	}

	symlinks := []struct {
		source string
		target string
		desc   string
	}{
		{
			source: filepath.Join(homeDir, ".config", "DankMaterialShell", "settings.json"),
			target: filepath.Join(cacheDir, "settings.json"),
			desc:   "Settings",
		},
		{
			source: filepath.Join(homeDir, ".local", "state", "DankMaterialShell", "session.json"),
			target: filepath.Join(cacheDir, "session.json"),
			desc:   "Session state",
		},
		{
			source: colorSyncInfo.SourcePath,
			target: filepath.Join(cacheDir, "colors.json"),
			desc:   colorThemeDesc,
		},
	}

	for _, link := range symlinks {
		targetInfo, err := os.Lstat(link.target)
		if err != nil {
			fmt.Printf("  ✗ %s: symlink not found at %s\n", link.desc, link.target)
			allGood = false
			continue
		}

		if targetInfo.Mode()&os.ModeSymlink == 0 {
			fmt.Printf("  ✗ %s: %s is not a symlink\n", link.desc, link.target)
			allGood = false
			continue
		}

		linkDest, err := os.Readlink(link.target)
		if err != nil {
			fmt.Printf("  ✗ %s: failed to read symlink\n", link.desc)
			allGood = false
			continue
		}

		if linkDest != link.source {
			fmt.Printf("  ✗ %s: symlink points to wrong location\n", link.desc)
			fmt.Printf("    Expected: %s\n", link.source)
			fmt.Printf("    Got: %s\n", linkDest)
			allGood = false
			continue
		}

		if _, err := os.Stat(link.source); os.IsNotExist(err) {
			fmt.Printf("  ⚠ %s: symlink OK, but source file doesn't exist yet\n", link.desc)
			fmt.Printf("    Will be created when you run DMS\n")
			continue
		}

		fmt.Printf("  ✓ %s: synced correctly\n", link.desc)
	}

	if colorSyncInfo.UsesDynamicWallpaperOverride {
		fmt.Printf("  ℹ Dynamic theme uses greeter override colors from %s\n", colorSyncInfo.SourcePath)
	}

	fmt.Println("\nGreeter Wallpaper Override:")
	overridePath := filepath.Join(cacheDir, "greeter_wallpaper_override.jpg")
	if stat, err := os.Stat(overridePath); err == nil && !stat.IsDir() {
		fmt.Printf("  ✓ Override file present: %s\n", overridePath)
	} else if os.IsNotExist(err) {
		fmt.Println("  ℹ Override file not present (desktop/session wallpaper fallback in effect)")
	} else if err != nil {
		fmt.Printf("  ✗ Could not inspect override file: %v\n", err)
		allGood = false
	} else {
		fmt.Printf("  ✗ Override path is not a regular file: %s\n", overridePath)
		allGood = false
	}

	fmt.Println("\nGreeter PAM Authentication (DMS-managed block):")
	if greeter.IsNixOS() {
		fmt.Println("  ℹ NixOS detected: PAM is managed by NixOS modules.")
		fmt.Println("    Configure fingerprint/U2F via your greetd NixOS module (security.pam.services.greetd).")
		fmt.Println()
		printGreeterStatusSummary(allGood, inGreeterGroup, greeterGroup)
		return nil
	}
	greetdPamPath := "/etc/pam.d/greetd"
	pamData, err := os.ReadFile(greetdPamPath)
	if err != nil {
		fmt.Printf("  ✗ Failed to read %s: %v\n", greetdPamPath, err)
		allGood = false
	} else {
		managed, managedFprint, managedU2f, legacyManaged := sharedpam.ParseManagedGreeterPamAuth(string(pamData))
		if managed {
			fmt.Println("  ✓ Managed auth block present")
			if managedFprint {
				fmt.Println("    - fingerprint: enabled")
			} else {
				fmt.Println("    - fingerprint: disabled")
			}
			if managedU2f {
				fmt.Println("    - security key (U2F): enabled")
			} else {
				fmt.Println("    - security key (U2F): disabled")
			}
		} else {
			fmt.Println("  ℹ No managed auth block present (DMS-managed fingerprint/U2F lines are disabled)")
		}
		if legacyManaged {
			fmt.Println("  ⚠ Legacy unmanaged DMS PAM lines detected. Run 'dms-greeter sync' to normalize.")
			allGood = false
		}
		enableFprintToggle, enableU2fToggle := false, false
		if enableFprint, enableU2f, settingsErr := sharedpam.ReadGreeterAuthToggles(homeDir); settingsErr == nil {
			enableFprintToggle = enableFprint
			enableU2fToggle = enableU2f
		} else {
			fmt.Printf("  ℹ Could not read greeter auth toggles from settings: %v\n", settingsErr)
		}

		includedFprintFile := sharedpam.DetectIncludedPamModule(string(pamData), "pam_fprintd.so")
		includedU2fFile := sharedpam.DetectIncludedPamModule(string(pamData), "pam_u2f.so")
		fprintAvailableForCurrentUser := sharedpam.FingerprintAuthAvailableForCurrentUser()

		if managedFprint && includedFprintFile != "" {
			fmt.Printf("  ⚠ pam_fprintd found in both DMS managed block and %s.\n", includedFprintFile)
			fmt.Println("    Double fingerprint auth detected — run 'dms-greeter sync' to resolve.")
			allGood = false
		}
		if managedU2f && includedU2fFile != "" {
			fmt.Printf("  ⚠ pam_u2f found in both DMS managed block and %s.\n", includedU2fFile)
			fmt.Println("    Double security-key auth detected — run 'dms-greeter sync' to resolve.")
			allGood = false
		}

		if includedFprintFile != "" && !managedFprint {
			switch {
			case enableFprintToggle && fprintAvailableForCurrentUser:
				fmt.Printf("  ℹ Fingerprint auth is enabled via included %s.\n", includedFprintFile)
				fmt.Println("    DMS toggle is enabled, and effective auth is coming from the included PAM stack.")
			case enableFprintToggle:
				fmt.Printf("  ℹ Fingerprint auth is enabled via included %s.\n", includedFprintFile)
				fmt.Println("    No enrolled fingerprints detected for the current user; password auth remains the effective path.")
			case fprintAvailableForCurrentUser:
				fmt.Printf("  ℹ Fingerprint auth is active via included %s while DMS fingerprint toggle is off.\n", includedFprintFile)
				fmt.Println("    Password login will work but may be delayed while the fingerprint module runs first.")
				fmt.Printf("    To eliminate the delay, %s\n", systemPamManagerRemediationHint())
			default:
				fmt.Printf("  ℹ pam_fprintd is present via included %s, but no enrolled fingerprints were detected for user %s.\n", includedFprintFile, currentUser.Username)
				fmt.Println("    Password auth remains the effective login path.")
			}
		}
		if includedU2fFile != "" && !managedU2f {
			if enableU2fToggle {
				fmt.Printf("  ℹ Security-key auth is enabled via included %s.\n", includedU2fFile)
				fmt.Println("    DMS toggle is enabled, but effective auth is coming from the included PAM stack.")
			} else {
				fmt.Printf("  ⚠ Security-key auth is active via included %s while DMS security-key toggle is off.\n", includedU2fFile)
				fmt.Printf("    %s\n", systemPamManagerRemediationHint())
			}
		}
	}

	fmt.Println("\nSecurity (AppArmor):")
	if !greeter.IsAppArmorEnabled() {
		fmt.Println("  ℹ AppArmor not enabled")
	} else {
		fmt.Println("  ℹ AppArmor is enabled")

		const appArmorProfilePath = "/etc/apparmor.d/usr.bin.dms-greeter"
		if _, err := os.Stat(appArmorProfilePath); os.IsNotExist(err) {
			fmt.Println("  ⚠ DMS AppArmor profile not installed")
			fmt.Println("    Run 'dms-greeter sync' to install it and prevent potential TTY fallback")
			allGood = false
		} else {
			mode := appArmorProfileMode("dms-greeter")
			if mode != "" {
				fmt.Printf("  ✓ DMS AppArmor profile installed (%s mode)\n", mode)
			} else {
				fmt.Println("  ✓ DMS AppArmor profile installed")
			}
		}

		denialCount, denialSamples, denialErr := recentAppArmorGreeterDenials(3)
		if denialErr != nil {
			fmt.Printf("  ℹ Could not inspect AppArmor denials automatically: %v\n", denialErr)
			fmt.Println("    If greetd falls back to TTY, run: sudo journalctl -b -k | grep 'apparmor.*DENIED'")
		} else if denialCount > 0 {
			fmt.Printf("  ⚠ Found %d recent AppArmor denial(s) related to greeter runtime.\n", denialCount)
			fmt.Println("    This can cause greetd fallback to TTY (for example: 'Failed to create stream fd: Permission denied').")
			fmt.Println("    Review denials with: sudo journalctl -b -k | grep 'apparmor.*DENIED'")
			fmt.Println("    Then refine the profile with: sudo aa-logprof")
			for i, sample := range denialSamples {
				fmt.Printf("    %d) %s\n", i+1, sample)
			}
			allGood = false
		} else {
			fmt.Println("  ✓ No recent AppArmor denials detected for common greeter components")
		}
	}

	fmt.Println()
	printGreeterStatusSummary(allGood, inGreeterGroup, greeterGroup)

	return nil
}

func printGreeterStatusSummary(allGood, inGreeterGroup bool, greeterGroup string) {
	switch {
	case allGood && inGreeterGroup:
		fmt.Println("✓ All checks passed! Greeter is properly configured.")
	case !allGood:
		fmt.Println("⚠ Some issues detected. Run 'dms-greeter sync' to repair configuration.")
	default:
		fmt.Printf("⚠ User is not in %s group. Run 'dms-greeter sync' after adding group membership.\n", greeterGroup)
	}
}

func checkNixOSGreeterStatus() error {
	const configPath = "/etc/greetd/config.toml"

	configuredCommand := readDefaultSessionCommand(configPath)
	allGood := true

	fmt.Println("Greeter Configuration:")
	switch {
	case strings.Contains(configuredCommand, "dms-greeter"):
		fmt.Println("  ✓ DMS greeter command found")
		if wrapper := extractGreeterWrapperFromCommand(configuredCommand); wrapper != "" {
			fmt.Printf("  Command: %s\n", wrapper)
		}
	case configuredCommand != "":
		fmt.Println("  ⚠ greetd default session does not reference dms-greeter")
		allGood = false
	default:
		fmt.Printf("  ℹ No readable DMS command found in %s\n", configPath)
	}
	fmt.Println("  ℹ NixOS manages greeter configuration declaratively; apply changes through your NixOS module.")

	stateDir := greeterStatusStateDir(configuredCommand, true)
	fmt.Println("\nGreeter State Directory:")
	fmt.Printf("  Effective state dir: %s\n", stateDir)
	if stateDir == nixOSGreeterStateDir {
		fmt.Println("  ✓ Using the NixOS module state path")
	}
	if stat, err := os.Stat(stateDir); err == nil && stat.IsDir() {
		fmt.Printf("  ✓ %s exists\n", stateDir)
	} else if os.IsNotExist(err) {
		fmt.Printf("  ✗ %s not found\n", stateDir)
		fmt.Println("    Rebuild your NixOS configuration after enabling the DMS greeter module.")
		allGood = false
	} else if err != nil {
		fmt.Printf("  ✗ Could not inspect %s: %v\n", stateDir, err)
		allGood = false
	} else {
		fmt.Printf("  ✗ %s is not a directory\n", stateDir)
		allGood = false
	}

	fmt.Println("\nDeclarative Configuration Files:")
	configFiles := []struct {
		name string
		path string
	}{
		{name: "Settings", path: filepath.Join(stateDir, "settings.json")},
		{name: "Session state", path: filepath.Join(stateDir, "session.json")},
		{name: "Color theme", path: filepath.Join(stateDir, "colors.json")},
	}
	for _, configFile := range configFiles {
		if stat, err := os.Stat(configFile.path); err == nil && !stat.IsDir() {
			fmt.Printf("  ✓ %s: %s\n", configFile.name, configFile.path)
		} else if os.IsNotExist(err) {
			fmt.Printf("  ℹ %s not present (optional; configure configHome/configFiles in the NixOS module)\n", configFile.name)
		} else if err != nil {
			fmt.Printf("  ⚠ %s could not be inspected: %v\n", configFile.name, err)
		} else {
			fmt.Printf("  ⚠ %s path is not a regular file: %s\n", configFile.name, configFile.path)
		}
	}

	fmt.Println("\nGroup Membership:")
	fmt.Println("  ℹ User group membership is managed by NixOS and is not required for declarative theme copies.")

	fmt.Println("\nGreeter PAM Authentication:")
	fmt.Println("  ℹ PAM is managed by NixOS modules.")
	fmt.Println("    Configure fingerprint/U2F through security.pam.services.greetd.")

	fmt.Println()
	if allGood {
		fmt.Println("✓ NixOS greeter state looks healthy and is managed declaratively.")
	} else {
		fmt.Println("⚠ Some issues detected. Update the DMS greeter module and rebuild NixOS; do not run 'dms-greeter sync'.")
	}

	return nil
}

func recentAppArmorGreeterDenials(sampleLimit int) (int, []string, error) {
	if sampleLimit <= 0 {
		sampleLimit = 3
	}
	if !utils.CommandExists("journalctl") {
		return 0, nil, fmt.Errorf("journalctl not found")
	}

	queries := [][]string{
		{"-b", "-k", "--no-pager", "-n", "2000", "-o", "cat"},
		{"-b", "--no-pager", "-n", "2000", "-o", "cat"},
	}

	seen := make(map[string]bool)
	samples := make([]string, 0, sampleLimit)
	total := 0
	var lastErr error
	successfulQuery := false

	for _, query := range queries {
		cmd := exec.Command("journalctl", query...)
		output, err := cmd.CombinedOutput()
		if err != nil {
			lastErr = err
			continue
		}
		successfulQuery = true
		total += collectGreeterAppArmorDenials(string(output), seen, &samples, sampleLimit)
	}

	if !successfulQuery && lastErr != nil {
		return 0, nil, lastErr
	}

	return total, samples, nil
}

func collectGreeterAppArmorDenials(text string, seen map[string]bool, samples *[]string, sampleLimit int) int {
	count := 0
	for _, rawLine := range strings.Split(text, "\n") {
		line := strings.TrimSpace(rawLine)
		if line == "" || !isGreeterRelatedAppArmorDenial(line) {
			continue
		}
		if seen[line] {
			continue
		}
		seen[line] = true
		count++
		if len(*samples) < sampleLimit {
			*samples = append(*samples, line)
		}
	}
	return count
}

func isGreeterRelatedAppArmorDenial(line string) bool {
	lower := strings.ToLower(line)
	if !strings.Contains(lower, "apparmor") || !strings.Contains(lower, "denied") {
		return false
	}

	greeterTokens := []string{
		"dms-greeter",
		"/usr/bin/dms-greeter",
		"greetd",
		"quickshell",
		"/usr/bin/qs",
		"/usr/bin/quickshell",
		"niri",
		"hyprland",
		"sway",
		"mango",
		"miracle",
		"labwc",
		"pipewire",
		"wireplumber",
		"stream fd",
	}

	for _, token := range greeterTokens {
		if strings.Contains(lower, token) {
			return true
		}
	}
	return false
}

// appArmorProfileMode returns "complain", "enforce", or "" for a named AppArmor profile.
func appArmorProfileMode(profileName string) string {
	data, err := os.ReadFile("/sys/kernel/security/apparmor/profiles")
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if !strings.Contains(line, profileName) {
			continue
		}
		lower := strings.ToLower(line)
		if strings.Contains(lower, "(complain)") {
			return "complain"
		}
		if strings.Contains(lower, "(enforce)") {
			return "enforce"
		}
		if strings.Contains(lower, "(kill)") {
			return "kill"
		}
	}
	return ""
}
