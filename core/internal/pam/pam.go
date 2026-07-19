// Package pam manages the DMS-managed auth block in /etc/pam.d/greetd
// (fingerprint / U2F lines for the greeter). Marker strings are kept
// byte-identical to DankMaterialShell so blocks written by older DMS
// versions are recognized.
package pam

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/AvengeMedia/dank-greeter/core/internal/distros"
	"github.com/AvengeMedia/dank-greeter/core/internal/privesc"
)

const (
	GreeterPamManagedBlockStart = "# BEGIN DMS GREETER AUTH (managed by dms greeter sync)"
	GreeterPamManagedBlockEnd   = "# END DMS GREETER AUTH"

	legacyGreeterPamFprintComment = "# DMS greeter fingerprint"
	legacyGreeterPamU2FComment    = "# DMS greeter U2F"

	GreetdPamPath = "/etc/pam.d/greetd"
)

var includedPamAuthFiles = []string{
	"system-auth",
	"common-auth",
	"password-auth",
	"system-login",
	"system-local-login",
	"common-auth-pc",
	"login",
}

type AuthSettings struct {
	GreeterEnableFprint         bool `json:"greeterEnableFprint"`
	GreeterEnableU2f            bool `json:"greeterEnableU2f"`
	GreeterPamExternallyManaged bool `json:"greeterPamExternallyManaged"`
}

type SyncAuthOptions struct {
	HomeDir          string
	ForceGreeterAuth bool
}

type syncDeps struct {
	pamDir                             string
	greetdPath                         string
	isNixOS                            func() bool
	readFile                           func(string) ([]byte, error)
	stat                               func(string) (os.FileInfo, error)
	createTemp                         func(string, string) (*os.File, error)
	removeFile                         func(string) error
	runSudoCmd                         func(string, string, ...string) error
	pamModuleExists                    func(string) bool
	fingerprintAvailableForCurrentUser func() bool
}

func defaultSyncDeps() syncDeps {
	return syncDeps{
		pamDir:     "/etc/pam.d",
		greetdPath: GreetdPamPath,
		isNixOS:    IsNixOS,
		readFile:   os.ReadFile,
		stat:       os.Stat,
		createTemp: os.CreateTemp,
		removeFile: os.Remove,
		runSudoCmd: func(password, command string, args ...string) error {
			return privesc.Run(context.Background(), password, append([]string{command}, args...)...)
		},
		pamModuleExists:                    pamModuleExists,
		fingerprintAvailableForCurrentUser: FingerprintAuthAvailableForCurrentUser,
	}
}

func IsNixOS() bool {
	_, err := os.Stat("/etc/NIXOS")
	return err == nil
}

// ReadAuthSettings reads the greeter auth toggles from the user's DMS
// settings; DMS Settings remains the front-end for these values.
func ReadAuthSettings(homeDir string) (AuthSettings, error) {
	settingsPath := filepath.Join(homeDir, ".config", "DankMaterialShell", "settings.json")
	data, err := os.ReadFile(settingsPath)
	if err != nil {
		if os.IsNotExist(err) {
			return AuthSettings{}, nil
		}
		return AuthSettings{}, fmt.Errorf("failed to read settings at %s: %w", settingsPath, err)
	}
	if strings.TrimSpace(string(data)) == "" {
		return AuthSettings{}, nil
	}

	var settings AuthSettings
	if err := json.Unmarshal(data, &settings); err != nil {
		return AuthSettings{}, fmt.Errorf("failed to parse settings at %s: %w", settingsPath, err)
	}
	return settings, nil
}

func ReadGreeterAuthToggles(homeDir string) (enableFprint bool, enableU2f bool, err error) {
	settings, err := ReadAuthSettings(homeDir)
	if err != nil {
		return false, false, err
	}
	return settings.GreeterEnableFprint, settings.GreeterEnableU2f, nil
}

func SyncAuthConfig(logFunc func(string), sudoPassword string, options SyncAuthOptions) error {
	return syncAuthConfigWithDeps(logFunc, sudoPassword, options, defaultSyncDeps())
}

func RemoveManagedGreeterPamBlock(logFunc func(string), sudoPassword string) error {
	return removeManagedGreeterPamBlockWithDeps(logFunc, sudoPassword, defaultSyncDeps())
}

func syncAuthConfigWithDeps(logFunc func(string), sudoPassword string, options SyncAuthOptions, deps syncDeps) error {
	homeDir := strings.TrimSpace(options.HomeDir)
	if homeDir == "" {
		var err error
		homeDir, err = os.UserHomeDir()
		if err != nil {
			return fmt.Errorf("failed to get user home directory: %w", err)
		}
	}

	settings, err := ReadAuthSettings(homeDir)
	if err != nil {
		return err
	}

	if _, err := deps.stat(deps.greetdPath); err != nil {
		if os.IsNotExist(err) {
			logFunc("ℹ /etc/pam.d/greetd not found. Skipping greeter PAM sync.")
			return nil
		}
		return fmt.Errorf("failed to inspect %s: %w", deps.greetdPath, err)
	}

	if settings.GreeterPamExternallyManaged {
		if err := removeManagedGreeterPamBlockWithDeps(logFunc, sudoPassword, deps); err != nil {
			return err
		}
		logFunc("ℹ /etc/pam.d/greetd is externally managed. Skipping DMS greeter PAM sync.")
		return nil
	}

	return syncGreeterPamConfigWithDeps(logFunc, sudoPassword, settings, options.ForceGreeterAuth, deps)
}

func removeManagedGreeterPamBlockWithDeps(logFunc func(string), sudoPassword string, deps syncDeps) error {
	if deps.isNixOS() {
		return nil
	}

	data, err := deps.readFile(deps.greetdPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return fmt.Errorf("failed to read %s: %w", deps.greetdPath, err)
	}

	originalContent := string(data)
	stripped, removed := stripManagedGreeterPamBlock(originalContent)
	strippedAgain, removedLegacy := stripLegacyGreeterPamLines(stripped)
	if !removed && !removedLegacy {
		return nil
	}

	if err := writeManagedPamFile(strippedAgain, deps.greetdPath, sudoPassword, deps); err != nil {
		return fmt.Errorf("failed to write %s: %w", deps.greetdPath, err)
	}

	logFunc("✓ Removed DMS managed PAM block from " + deps.greetdPath)
	return nil
}

func ParseManagedGreeterPamAuth(pamText string) (managed bool, fingerprint bool, u2f bool, legacy bool) {
	if pamText == "" {
		return false, false, false, false
	}

	inManaged := false
	for line := range strings.SplitSeq(pamText, "\n") {
		trimmed := strings.TrimSpace(line)
		switch trimmed {
		case GreeterPamManagedBlockStart:
			managed = true
			inManaged = true
			continue
		case GreeterPamManagedBlockEnd:
			inManaged = false
			continue
		}

		if strings.HasPrefix(trimmed, legacyGreeterPamFprintComment) || strings.HasPrefix(trimmed, legacyGreeterPamU2FComment) {
			legacy = true
		}
		if !inManaged {
			continue
		}
		if strings.Contains(trimmed, "pam_fprintd") {
			fingerprint = true
		}
		if strings.Contains(trimmed, "pam_u2f") {
			u2f = true
		}
	}

	return managed, fingerprint, u2f, legacy
}

func StripManagedGreeterPamContent(pamText string) (string, bool) {
	stripped, removed := stripManagedGreeterPamBlock(pamText)
	stripped, removedLegacy := stripLegacyGreeterPamLines(stripped)
	return stripped, removed || removedLegacy
}

func PamTextIncludesFile(pamText, filename string) bool {
	for line := range strings.SplitSeq(pamText, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		if strings.Contains(trimmed, filename) &&
			(strings.Contains(trimmed, "include") || strings.Contains(trimmed, "substack") || strings.HasPrefix(trimmed, "@include")) {
			return true
		}
	}
	return false
}

func DetectIncludedPamModule(pamText, module string) string {
	return detectIncludedPamModule(pamText, module, defaultSyncDeps())
}

func detectIncludedPamModule(pamText, module string, deps syncDeps) string {
	for _, includedFile := range includedPamAuthFiles {
		if !PamTextIncludesFile(pamText, includedFile) {
			continue
		}
		data, err := deps.readFile(filepath.Join(deps.pamDir, includedFile))
		if err != nil {
			continue
		}
		if pamContentHasModule(string(data), module) {
			return includedFile
		}
	}
	return ""
}

func pamContentHasModule(content, module string) bool {
	for line := range strings.SplitSeq(content, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		if strings.Contains(trimmed, module) {
			return true
		}
	}
	return false
}

func stripManagedGreeterPamBlock(content string) (string, bool) {
	lines := strings.Split(content, "\n")
	filtered := make([]string, 0, len(lines))
	inManagedBlock := false
	removed := false

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == GreeterPamManagedBlockStart {
			inManagedBlock = true
			removed = true
			continue
		}
		if trimmed == GreeterPamManagedBlockEnd {
			inManagedBlock = false
			removed = true
			continue
		}
		if inManagedBlock {
			removed = true
			continue
		}
		filtered = append(filtered, line)
	}

	return strings.Join(filtered, "\n"), removed
}

func stripLegacyGreeterPamLines(content string) (string, bool) {
	lines := strings.Split(content, "\n")
	filtered := make([]string, 0, len(lines))
	removed := false

	for i := 0; i < len(lines); i++ {
		trimmed := strings.TrimSpace(lines[i])
		if strings.HasPrefix(trimmed, legacyGreeterPamFprintComment) || strings.HasPrefix(trimmed, legacyGreeterPamU2FComment) {
			removed = true
			if i+1 < len(lines) {
				nextLine := strings.TrimSpace(lines[i+1])
				if strings.HasPrefix(nextLine, "auth") &&
					(strings.Contains(nextLine, "pam_fprintd") || strings.Contains(nextLine, "pam_u2f")) {
					i++
				}
			}
			continue
		}
		filtered = append(filtered, lines[i])
	}

	return strings.Join(filtered, "\n"), removed
}

func insertManagedGreeterPamBlock(content string, blockLines []string, greetdPamPath string) (string, error) {
	lines := strings.Split(content, "\n")
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") || !strings.HasPrefix(trimmed, "auth") {
			continue
		}

		block := strings.Join(blockLines, "\n")
		prefix := strings.Join(lines[:i], "\n")
		suffix := strings.Join(lines[i:], "\n")
		switch {
		case prefix == "":
			return block + "\n" + suffix, nil
		case suffix == "":
			return prefix + "\n" + block, nil
		default:
			return prefix + "\n" + block + "\n" + suffix, nil
		}
	}
	return "", fmt.Errorf("no auth directive found in %s", greetdPamPath)
}

func syncGreeterPamConfigWithDeps(logFunc func(string), sudoPassword string, settings AuthSettings, forceAuth bool, deps syncDeps) error {
	var wantFprint, wantU2f bool
	fprintToggleEnabled := forceAuth
	u2fToggleEnabled := forceAuth
	if forceAuth {
		wantFprint = deps.pamModuleExists("pam_fprintd.so")
		wantU2f = deps.pamModuleExists("pam_u2f.so")
	} else {
		fprintToggleEnabled = settings.GreeterEnableFprint
		u2fToggleEnabled = settings.GreeterEnableU2f
		fprintModule := deps.pamModuleExists("pam_fprintd.so")
		u2fModule := deps.pamModuleExists("pam_u2f.so")
		wantFprint = settings.GreeterEnableFprint && fprintModule
		wantU2f = settings.GreeterEnableU2f && u2fModule
		if settings.GreeterEnableFprint && !fprintModule {
			logFunc("⚠ Warning: greeter fingerprint toggle is enabled, but pam_fprintd.so was not found.")
		}
		if settings.GreeterEnableU2f && !u2fModule {
			logFunc("⚠ Warning: greeter security key toggle is enabled, but pam_u2f.so was not found.")
		}
	}

	if deps.isNixOS() {
		logFunc("ℹ NixOS detected: PAM config is managed by NixOS modules. Skipping DMS PAM block write.")
		logFunc("  Configure fingerprint/U2F auth via your greetd NixOS module options (e.g. security.pam.services.greetd).")
		return nil
	}

	pamData, err := deps.readFile(deps.greetdPath)
	if err != nil {
		return fmt.Errorf("failed to read %s: %w", deps.greetdPath, err)
	}
	originalContent := string(pamData)
	content, _ := stripManagedGreeterPamBlock(originalContent)
	content, _ = stripLegacyGreeterPamLines(content)

	includedFprintFile := detectIncludedPamModule(content, "pam_fprintd.so", deps)
	includedU2fFile := detectIncludedPamModule(content, "pam_u2f.so", deps)
	fprintAvailableForCurrentUser := deps.fingerprintAvailableForCurrentUser()
	if wantFprint && includedFprintFile != "" {
		logFunc("⚠ pam_fprintd already present in included " + includedFprintFile + " (managed by authselect/pam-auth-update). Skipping DMS fprint block to avoid double-fingerprint auth.")
		wantFprint = false
	}
	if wantU2f && includedU2fFile != "" {
		logFunc("⚠ pam_u2f already present in included " + includedU2fFile + " (managed by authselect/pam-auth-update). Skipping DMS U2F block to avoid double security-key auth.")
		wantU2f = false
	}
	if !wantFprint && includedFprintFile != "" {
		switch {
		case fprintToggleEnabled && fprintAvailableForCurrentUser:
			logFunc("ℹ Fingerprint auth is still enabled via included " + includedFprintFile + ".")
			logFunc("  DMS toggle is enabled, and effective auth is provided by the included PAM stack.")
		case fprintToggleEnabled:
			logFunc("ℹ Fingerprint auth is still enabled via included " + includedFprintFile + ".")
			logFunc("  No enrolled fingerprints detected for the current user; password auth remains the effective path.")
		case fprintAvailableForCurrentUser:
			logFunc("ℹ Fingerprint auth is active via included " + includedFprintFile + " while DMS fingerprint toggle is off.")
			logFunc("  Password login will work but may be delayed while the fingerprint module runs first.")
			logFunc("  To eliminate the delay, " + pamManagerHintForCurrentDistro())
		default:
			logFunc("ℹ pam_fprintd is present via included " + includedFprintFile + ", but no enrolled fingerprints were detected for the current user.")
			logFunc("  Password auth remains the effective login path.")
		}
	}
	if !wantU2f && includedU2fFile != "" {
		if u2fToggleEnabled {
			logFunc("ℹ Security-key auth is still enabled via included " + includedU2fFile + ".")
			logFunc("  DMS toggle is enabled, but effective auth is provided by the included PAM stack.")
		} else {
			logFunc("⚠ Security-key auth is active via included " + includedU2fFile + " while DMS security-key toggle is off.")
			logFunc("  " + pamManagerHintForCurrentDistro())
		}
	}

	if wantFprint || wantU2f {
		blockLines := []string{GreeterPamManagedBlockStart}
		if wantFprint {
			blockLines = append(blockLines, "auth sufficient pam_fprintd.so max-tries=2 timeout=10")
		}
		if wantU2f {
			blockLines = append(blockLines, "auth sufficient pam_u2f.so cue nouserok timeout=10")
		}
		blockLines = append(blockLines, GreeterPamManagedBlockEnd)

		content, err = insertManagedGreeterPamBlock(content, blockLines, deps.greetdPath)
		if err != nil {
			return err
		}
	}

	if content == originalContent {
		return nil
	}

	if err := writeManagedPamFile(content, deps.greetdPath, sudoPassword, deps); err != nil {
		return fmt.Errorf("failed to install updated PAM config at %s: %w", deps.greetdPath, err)
	}
	if wantFprint || wantU2f {
		logFunc("✓ Configured greetd PAM for fingerprint/U2F")
	} else {
		logFunc("✓ Cleared DMS-managed greeter PAM auth block")
	}
	return nil
}

func writeManagedPamFile(content string, destPath string, sudoPassword string, deps syncDeps) error {
	tmpFile, err := deps.createTemp("", "dms-pam-*.conf")
	if err != nil {
		return err
	}
	tmpPath := tmpFile.Name()
	defer func() {
		_ = deps.removeFile(tmpPath)
	}()

	if _, err := tmpFile.WriteString(content); err != nil {
		tmpFile.Close()
		return err
	}
	if err := tmpFile.Close(); err != nil {
		return err
	}
	if err := deps.runSudoCmd(sudoPassword, "cp", tmpPath, destPath); err != nil {
		return err
	}
	if err := deps.runSudoCmd(sudoPassword, "chmod", "644", destPath); err != nil {
		return fmt.Errorf("failed to set permissions on %s: %w", destPath, err)
	}
	return nil
}

func pamManagerHintForCurrentDistro() string {
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

func pamModuleExists(module string) bool {
	for _, libDir := range []string{
		"/usr/lib64/security",
		"/usr/lib/security",
		"/lib64/security",
		"/lib/security",
		"/lib/x86_64-linux-gnu/security",
		"/usr/lib/x86_64-linux-gnu/security",
		"/lib/aarch64-linux-gnu/security",
		"/usr/lib/aarch64-linux-gnu/security",
		"/run/current-system/sw/lib64/security",
		"/run/current-system/sw/lib/security",
	} {
		if _, err := os.Stat(filepath.Join(libDir, module)); err == nil {
			return true
		}
	}
	return false
}

func hasEnrolledFingerprintOutput(output string) bool {
	lower := strings.ToLower(output)
	if strings.Contains(lower, "no fingers enrolled") ||
		strings.Contains(lower, "no fingerprints enrolled") ||
		strings.Contains(lower, "no prints enrolled") {
		return false
	}
	if strings.Contains(lower, "has fingers enrolled") ||
		strings.Contains(lower, "has fingerprints enrolled") {
		return true
	}
	for line := range strings.SplitSeq(lower, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "finger:") {
			return true
		}
		if strings.HasPrefix(trimmed, "- ") && strings.Contains(trimmed, "finger") {
			return true
		}
	}
	return false
}

func FingerprintAuthAvailableForCurrentUser() bool {
	username := strings.TrimSpace(os.Getenv("SUDO_USER"))
	if username == "" {
		username = strings.TrimSpace(os.Getenv("USER"))
	}
	if username == "" {
		out, err := exec.Command("id", "-un").Output()
		if err == nil {
			username = strings.TrimSpace(string(out))
		}
	}
	return fingerprintAuthAvailableForUser(username)
}

func fingerprintAuthAvailableForUser(username string) bool {
	username = strings.TrimSpace(username)
	if username == "" {
		return false
	}
	if !pamModuleExists("pam_fprintd.so") {
		return false
	}
	if _, err := exec.LookPath("fprintd-list"); err != nil {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "fprintd-list", username).CombinedOutput()
	if err != nil {
		return false
	}
	return hasEnrolledFingerprintOutput(string(out))
}
