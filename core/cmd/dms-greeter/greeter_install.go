package main

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/AvengeMedia/dank-greeter/core/internal/greeter"
	sharedpam "github.com/AvengeMedia/dank-greeter/core/internal/pam"
	"github.com/AvengeMedia/dank-greeter/core/internal/privesc"
	"github.com/AvengeMedia/dank-greeter/core/internal/utils"
)

func installGreeter(nonInteractive bool) error {
	fmt.Println("=== DMS Greeter Installation ===")

	logFunc := func(msg string) {
		fmt.Println(msg)
	}

	if !nonInteractive {
		fmt.Print("\nThis will install greetd (if needed), configure the DMS greeter, and enable it. Continue? [Y/n]: ")
		var response string
		fmt.Scanln(&response)
		if strings.ToLower(strings.TrimSpace(response)) == "n" || strings.ToLower(strings.TrimSpace(response)) == "no" {
			fmt.Println("Aborted.")
			return nil
		}
		fmt.Println()
	}

	if err := greeter.EnsureGreetdInstalled(logFunc, ""); err != nil {
		return err
	}

	if err := rejectLegacyWrapper(); err != nil {
		return err
	}

	if isGreeterEnabled() && !nonInteractive {
		fmt.Print("\nGreeter is already installed and configured. Re-run to re-sync settings and permissions? [Y/n]: ")
		var response string
		fmt.Scanln(&response)
		response = strings.TrimSpace(strings.ToLower(response))
		if response == "n" || response == "no" {
			fmt.Println("Run 'dms-greeter sync' to re-sync theme and settings at any time.")
			return nil
		}
		fmt.Println()
	}

	fmt.Println("\nDetecting installed compositors...")
	compositors := greeter.DetectCompositors()
	if len(compositors) == 0 {
		return fmt.Errorf("no supported compositors found (niri or Hyprland required)")
	}

	var selectedCompositor string
	if len(compositors) == 1 {
		selectedCompositor = compositors[0]
		fmt.Printf("✓ Found compositor: %s\n", selectedCompositor)
	} else {
		var err error
		selectedCompositor, err = promptCompositorChoice(compositors)
		if err != nil {
			return err
		}
		fmt.Printf("✓ Selected compositor: %s\n", selectedCompositor)
	}

	fmt.Println("\nSetting up dms-greeter group and permissions...")
	if err := greeter.SetupDMSGroup(logFunc, ""); err != nil {
		return err
	}

	fmt.Println("\nSetting up greeter cache directory...")
	if err := greeter.EnsureGreeterCacheDir(logFunc, ""); err != nil {
		return err
	}

	if greeter.IsAppArmorEnabled() {
		fmt.Println("\nConfiguring AppArmor profile...")
		if err := greeter.InstallAppArmorProfile(logFunc, ""); err != nil {
			logFunc(fmt.Sprintf("⚠ AppArmor profile setup failed: %v", err))
		}
	}

	fmt.Println("\nConfiguring greetd...")
	if err := greeter.ConfigureGreetd("", selectedCompositor, logFunc, ""); err != nil {
		return err
	}

	fmt.Println("\nSynchronizing DMS configurations...")
	if err := syncGreeterConfigsAndAuth(selectedCompositor, logFunc, sharedpam.SyncAuthOptions{}, func() {
		fmt.Println("\nConfiguring authentication...")
	}); err != nil {
		return err
	}

	if err := ensureGraphicalTarget(); err != nil {
		return err
	}

	if err := handleConflictingDisplayManagers(); err != nil {
		return err
	}

	if err := ensureGreetdEnabled(); err != nil {
		return err
	}

	fmt.Println("\n=== Installation Complete ===")
	fmt.Println("\nTo start the greeter now, run:")
	fmt.Println(startGreeterHint())
	fmt.Println("\nOr reboot to see the greeter at next boot.")

	return nil
}

func enableGreeter(nonInteractive bool) error {
	fmt.Println("=== DMS Greeter Enable ===")
	fmt.Println()

	configPath := "/etc/greetd/config.toml"
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		return fmt.Errorf("greetd config not found at %s\nPlease install greetd first", configPath)
	} else if err != nil {
		return fmt.Errorf("failed to access greetd config at %s: %w", configPath, err)
	}

	if err := rejectLegacyWrapper(); err != nil {
		return err
	}

	configAlreadyCorrect := isGreeterEnabled()
	configuredCompositor := detectConfiguredCompositor()

	logFunc := func(msg string) {
		fmt.Println(msg)
	}
	if configAlreadyCorrect {
		fmt.Println("✓ Greeter is already configured with dms-greeter")
		if configuredCompositor != "" {
			fmt.Printf("✓ Configured compositor: %s\n", configuredCompositor)
		}

		fmt.Println("\nSetting up dms-greeter group and permissions...")
		if err := greeter.SetupDMSGroup(logFunc, ""); err != nil {
			return err
		}
		if err := greeter.EnsureGreeterCacheDir(logFunc, ""); err != nil {
			return fmt.Errorf("failed to prepare greeter cache: %w", err)
		}
		if err := greeter.EnsureVoidLogindGreetdCommand(logFunc, ""); err != nil {
			return err
		}

		if err := ensureGraphicalTarget(); err != nil {
			return err
		}

		if err := handleConflictingDisplayManagers(); err != nil {
			return err
		}

		if err := ensureGreetdEnabled(); err != nil {
			return err
		}

		fmt.Println("\n=== Enable Complete ===")
		fmt.Println("\nGreeter configuration verified and system state corrected.")
		fmt.Println("To start the greeter now, run:")
		fmt.Println(startGreeterHint())
		fmt.Println("\nOr reboot to see the greeter at boot time.")

		return nil
	}

	if !nonInteractive {
		fmt.Print("\nThis will configure greetd to use the DMS greeter and may disable other display managers. Continue? [Y/n]: ")
		var response string
		fmt.Scanln(&response)
		if strings.ToLower(strings.TrimSpace(response)) == "n" || strings.ToLower(strings.TrimSpace(response)) == "no" {
			fmt.Println("Aborted.")
			return nil
		}
		fmt.Println()
	}

	fmt.Println("Detecting installed compositors...")
	compositors := greeter.DetectCompositors()

	if utils.CommandExists("sway") {
		compositors = append(compositors, "sway")
	}

	if len(compositors) == 0 {
		return fmt.Errorf("no supported compositors found (niri, Hyprland, or sway required)")
	}

	var selectedCompositor string
	if len(compositors) == 1 {
		selectedCompositor = compositors[0]
		fmt.Printf("✓ Found compositor: %s\n", selectedCompositor)
	} else {
		var err error
		selectedCompositor, err = promptCompositorChoice(compositors)
		if err != nil {
			return err
		}
		fmt.Printf("✓ Selected compositor: %s\n", selectedCompositor)
	}

	if err := greeter.ConfigureGreetd("", selectedCompositor, logFunc, ""); err != nil {
		return fmt.Errorf("failed to configure greetd: %w", err)
	}

	fmt.Println("\nSetting up dms-greeter group and permissions...")
	if err := greeter.SetupDMSGroup(logFunc, ""); err != nil {
		return err
	}
	if err := greeter.EnsureGreeterCacheDir(logFunc, ""); err != nil {
		return fmt.Errorf("failed to prepare greeter cache: %w", err)
	}

	if greeter.IsAppArmorEnabled() {
		if err := greeter.InstallAppArmorProfile(logFunc, ""); err != nil {
			logFunc(fmt.Sprintf("⚠ AppArmor profile setup failed: %v", err))
		}
	}

	if err := ensureGraphicalTarget(); err != nil {
		return err
	}

	if err := handleConflictingDisplayManagers(); err != nil {
		return err
	}

	if err := ensureGreetdEnabled(); err != nil {
		return err
	}

	fmt.Println("\n=== Enable Complete ===")
	fmt.Println("\nTo start the greeter now, run:")
	fmt.Println(startGreeterHint())
	fmt.Println("\nOr reboot to see the greeter at boot time.")

	return nil
}

func uninstallGreeter(nonInteractive bool) error {
	fmt.Println("=== DMS Greeter Uninstall ===")

	logFunc := func(msg string) { fmt.Println(msg) }

	if !isGreeterEnabled() {
		fmt.Println("ℹ DMS greeter is not currently configured in /etc/greetd/config.toml.")
		fmt.Println("  Nothing to undo for greetd configuration.")
	}

	if !nonInteractive {
		fmt.Print("\nThis will:\n  • Stop and disable greetd\n  • Remove the DMS-managed greeter auth block\n  • Remove the DMS AppArmor profile\n  • Restore the most recent pre-DMS greetd config (if available)\n\nContinue? [y/N]: ")
		var response string
		fmt.Scanln(&response)
		if strings.ToLower(strings.TrimSpace(response)) != "y" {
			fmt.Println("Aborted.")
			return nil
		}
	}

	fmt.Println("\nDisabling greetd...")
	if isRunit() {
		if err := disableRunitService("greetd"); err != nil {
			fmt.Printf("  ⚠ Could not disable greetd: %v\n", err)
		} else {
			fmt.Println("  ✓ greetd disabled")
		}
	} else if err := privesc.Run(context.Background(), "", "systemctl", "disable", "greetd"); err != nil {
		fmt.Printf("  ⚠ Could not disable greetd: %v\n", err)
	} else {
		fmt.Println("  ✓ greetd disabled")
	}

	fmt.Println("\nRemoving DMS authentication configuration...")
	if err := sharedpam.RemoveManagedGreeterPamBlock(logFunc, ""); err != nil {
		fmt.Printf("  ⚠ PAM cleanup failed: %v\n", err)
	}

	fmt.Println("\nRemoving DMS AppArmor profile...")
	if err := greeter.UninstallAppArmorProfile(logFunc, ""); err != nil {
		fmt.Printf("  ⚠ AppArmor cleanup failed: %v\n", err)
	}

	cleanupLegacyWrapperInstall()

	fmt.Println("\nRestoring greetd configuration...")
	if err := restorePreDMSGreetdConfig(""); err != nil {
		fmt.Printf("  ⚠ Could not restore previous greetd config: %v\n", err)
		fmt.Println("  You may need to manually edit /etc/greetd/config.toml.")
	}

	fmt.Println("\nChecking for other display managers to re-enable...")
	suggestDisplayManagerRestore(nonInteractive)

	fmt.Println("\n=== Uninstall Complete ===")
	fmt.Println("\nReboot to complete the uninstallation and switch to your previous display manager.")
	fmt.Println("To re-enable DMS greeter at any time, run: dms-greeter enable")

	return nil
}

// cleanupLegacyWrapperInstall removes leftovers of the old bash-wrapper
// architecture: a manually installed wrapper script in /usr/local/bin.
// Packaged files (old /usr/bin wrapper, /usr/share/quickshell/dms-greeter)
// are left to the package manager.
func cleanupLegacyWrapperInstall() {
	const legacyWrapper = "/usr/local/bin/dms-greeter"
	for _, path := range greeter.LegacyWrapperScriptPaths() {
		if path != legacyWrapper {
			fmt.Printf("  ℹ Legacy wrapper script at %s belongs to the old dms-greeter package; remove it with your package manager.\n", path)
			continue
		}
		fmt.Println("\nRemoving legacy dms-greeter wrapper script...")
		if err := privesc.Run(context.Background(), "", "rm", "-f", path); err != nil {
			fmt.Printf("  ⚠ Could not remove %s: %v\n", path, err)
		} else {
			fmt.Printf("  ✓ Removed %s\n", path)
		}
	}
	if greeter.HasLegacyQuickshellTree() {
		fmt.Println("  ℹ Legacy greeter QML tree at /usr/share/quickshell/dms-greeter can be removed with the old dms-greeter package.")
	}
}

func restorePreDMSGreetdConfig(sudoPassword string) error {
	const configPath = "/etc/greetd/config.toml"
	const backupGlob = "/etc/greetd/config.toml.backup-*"

	matches, _ := filepath.Glob(backupGlob)

	for i := 0; i < len(matches)-1; i++ {
		for j := i + 1; j < len(matches); j++ {
			if matches[j] > matches[i] {
				matches[i], matches[j] = matches[j], matches[i]
			}
		}
	}

	for _, candidate := range matches {
		data, err := os.ReadFile(candidate)
		if err != nil {
			continue
		}
		if strings.Contains(string(data), "dms-greeter") {
			continue
		}
		tmp, err := os.CreateTemp("", "greetd-restore-*")
		if err != nil {
			return fmt.Errorf("could not create temp file: %w", err)
		}
		tmpPath := tmp.Name()
		defer os.Remove(tmpPath)
		if _, err := tmp.Write(data); err != nil {
			tmp.Close()
			return err
		}
		tmp.Close()

		if err := privesc.Run(context.Background(), sudoPassword, "cp", tmpPath, configPath); err != nil {
			return fmt.Errorf("failed to restore %s: %w", candidate, err)
		}
		if err := privesc.Run(context.Background(), sudoPassword, "chmod", "644", configPath); err != nil {
			return err
		}
		fmt.Printf("  ✓ Restored greetd config from %s\n", candidate)
		return nil
	}

	minimal := `[terminal]
vt = 1

# DMS greeter has been uninstalled.
# Configure a greeter command here or re-enable a display manager.
[default_session]
user = "greeter"
command = "agreety --cmd /bin/bash"
`
	tmp, err := os.CreateTemp("", "greetd-minimal-*")
	if err != nil {
		return fmt.Errorf("could not create temp file: %w", err)
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)
	if _, err := tmp.WriteString(minimal); err != nil {
		tmp.Close()
		return err
	}
	tmp.Close()

	if err := privesc.Run(context.Background(), sudoPassword, "cp", tmpPath, configPath); err != nil {
		return fmt.Errorf("failed to write fallback greetd config: %w", err)
	}
	_ = privesc.Run(context.Background(), sudoPassword, "chmod", "644", configPath)
	fmt.Println("  ✓ Wrote minimal fallback greetd config (configure a greeter command manually if needed)")
	return nil
}

// suggestDisplayManagerRestore scans for installed DMs and re-enables one
func suggestDisplayManagerRestore(nonInteractive bool) {
	knownDMs := []string{"gdm", "gdm3", "lightdm", "sddm", "lxdm", "xdm", "cosmic-greeter"}
	var found []string
	for _, dm := range knownDMs {
		if utils.CommandExists(dm) || isSystemdUnitInstalled(dm) {
			found = append(found, dm)
		}
	}
	if len(found) == 0 {
		fmt.Println("  ℹ No other display managers detected.")
		fmt.Println("  You can install one (e.g. gdm, lightdm, sddm) and then run:")
		fmt.Println("    sudo systemctl enable --now <dm-name>")
		return
	}

	enableDM := func(dm string) {
		fmt.Printf("  Enabling %s...\n", dm)
		if isRunit() {
			if err := enableRunitService(dm); err != nil {
				fmt.Printf("  ⚠ Failed to enable %s: %v\n", dm, err)
			} else {
				fmt.Printf("  ✓ %s enabled (linked into %s).\n", dm, runitServiceDir)
			}
			return
		}
		if err := privesc.Run(context.Background(), "", "systemctl", "enable", "--force", dm); err != nil {
			fmt.Printf("  ⚠ Failed to enable %s: %v\n", dm, err)
		} else {
			fmt.Printf("  ✓ %s enabled (will take effect on next boot).\n", dm)
		}
	}

	if len(found) == 1 || nonInteractive {
		chosen := found[0]
		if len(found) > 1 {
			fmt.Printf("  ℹ Multiple display managers found (%s); enabling %s automatically.\n",
				strings.Join(found, ", "), chosen)
		} else {
			fmt.Printf("  ℹ Found display manager: %s\n", chosen)
		}
		enableDM(chosen)
		return
	}

	fmt.Println("  ℹ Found the following display managers:")
	for i, dm := range found {
		fmt.Printf("    %d) %s\n", i+1, dm)
	}
	fmt.Print("  Choose a number to re-enable (or press Enter to skip): ")

	scanner := bufio.NewScanner(os.Stdin)
	if !scanner.Scan() {
		return
	}
	input := strings.TrimSpace(scanner.Text())
	if input == "" {
		fmt.Println("  Skipped. You can re-enable a display manager later with:")
		fmt.Println("    sudo systemctl enable --now <dm-name>")
		return
	}

	n, err := strconv.Atoi(input)
	if err != nil || n < 1 || n > len(found) {
		fmt.Printf("  Invalid selection %q — skipping.\n", input)
		return
	}

	enableDM(found[n-1])
}

func isSystemdUnitInstalled(unit string) bool {
	if isRunit() {
		return runitServiceInstalled(unit)
	}
	cmd := exec.Command("systemctl", "list-unit-files", unit+".service", "--no-legend", "--no-pager")
	out, err := cmd.Output()
	return err == nil && strings.Contains(string(out), unit)
}

func disableDisplayManager(dmName string) (bool, error) {
	if isRunit() {
		if !runitServiceEnabled(dmName) {
			return false, nil
		}
		fmt.Printf("\nDisabling %s (runit)...\n", dmName)
		if err := disableRunitService(dmName); err != nil {
			return false, fmt.Errorf("failed to disable %s: %w", dmName, err)
		}
		fmt.Printf("  ✓ %s disabled (removed from %s)\n", dmName, runitServiceDir)
		return true, nil
	}

	state, err := getSystemdServiceState(dmName)
	if err != nil {
		return false, fmt.Errorf("failed to check %s state: %w", dmName, err)
	}

	if !state.Exists {
		return false, nil
	}

	fmt.Printf("\nChecking %s...\n", dmName)
	fmt.Printf("  Current state: enabled=%s\n", state.EnabledState)

	if !state.NeedsDisable {
		if state.EnabledState == "masked" || state.EnabledState == "masked-runtime" {
			fmt.Printf("  ✓ %s is already masked\n", dmName)
		} else {
			fmt.Printf("  ✓ %s is already disabled\n", dmName)
		}
		return false, nil
	}

	var action, actionVerb string
	switch state.EnabledState {
	case "static":
		fmt.Printf("  Masking %s (static service cannot be disabled)...\n", dmName)
		action = "mask"
		actionVerb = "masked"
	default:
		fmt.Printf("  Disabling %s...\n", dmName)
		action = "disable"
		actionVerb = "disabled"
	}

	if err := privesc.Run(context.Background(), "", "systemctl", action, dmName); err != nil {
		return false, fmt.Errorf("failed to disable/mask %s: %w", dmName, err)
	}

	enabledState, shouldDisable, verifyErr := checkSystemdServiceEnabled(dmName)
	switch {
	case verifyErr != nil:
		fmt.Printf("  ⚠ Warning: Could not verify %s was %s: %v\n", dmName, actionVerb, verifyErr)
	case shouldDisable:
		return false, fmt.Errorf("%s is still in state '%s' after %s operation", dmName, enabledState, actionVerb)
	default:
		fmt.Printf("  ✓ %s %s (now: %s)\n", titleWord(actionVerb), dmName, enabledState)
	}

	return true, nil
}

func titleWord(word string) string {
	if word == "" {
		return word
	}
	return strings.ToUpper(word[:1]) + word[1:]
}

func handleConflictingDisplayManagers() error {
	fmt.Println("\n=== Checking for Conflicting Display Managers ===")

	conflictingDMs := []string{"gdm", "gdm3", "lightdm", "sddm", "lxdm", "xdm", "cosmic-greeter"}

	disabledAny := false
	var errors []string

	for _, dm := range conflictingDMs {
		actionTaken, err := disableDisplayManager(dm)
		if err != nil {
			errMsg := fmt.Sprintf("Failed to handle %s: %v", dm, err)
			errors = append(errors, errMsg)
			fmt.Printf("  ⚠⚠⚠ ERROR: %s\n", errMsg)
			continue
		}
		if actionTaken {
			disabledAny = true
		}
	}

	if len(errors) > 0 {
		fmt.Println("\n╔════════════════════════════════════════════════════════════╗")
		fmt.Println("║           ⚠⚠⚠ ERRORS OCCURRED ⚠⚠⚠                      ║")
		fmt.Println("╚════════════════════════════════════════════════════════════╝")
		fmt.Println("\nSome display managers could not be disabled:")
		for _, err := range errors {
			fmt.Printf("  ✗ %s\n", err)
		}
		fmt.Println("\nThis may prevent greetd from starting properly.")
		fmt.Println("You may need to manually disable them before greetd will work.")
		fmt.Println("\nManual commands to try:")
		for _, dm := range conflictingDMs {
			fmt.Printf("  sudo systemctl disable %s\n", dm)
			fmt.Printf("  sudo systemctl mask %s\n", dm)
		}
		fmt.Print("\nContinue with greeter enablement anyway? (Y/n): ")

		var response string
		fmt.Scanln(&response)
		response = strings.ToLower(strings.TrimSpace(response))

		if response == "n" || response == "no" {
			return fmt.Errorf("aborted due to display manager conflicts")
		}
		fmt.Println("\nContinuing despite errors...")
	}

	if !disabledAny && len(errors) == 0 {
		fmt.Println("\n✓ No conflicting display managers found")
	} else if disabledAny && len(errors) == 0 {
		fmt.Println("\n✓ Successfully handled all conflicting display managers")
	}

	return nil
}

func ensureGreetdEnabled() error {
	if isRunit() {
		fmt.Println("\nEnabling greetd service (runit)...")
		if !runitServiceInstalled("greetd") {
			return fmt.Errorf("greetd service not found in %s. Please install greetd first", runitSvDir)
		}
		if greeter.IsVoidLinux() {
			ensureVoidLogindGreeter("_greeter")
		} else {
			ensureRunitSeat("_greeter")
		}
		ensureGreetdPamRundir()
		if err := enableRunitService("greetd"); err != nil {
			return fmt.Errorf("failed to enable greetd: %w", err)
		}
		fmt.Printf("  ✓ greetd enabled (%s)\n", runitServiceDir)
		return nil
	}

	fmt.Println("\nChecking greetd service status...")

	state, err := getSystemdServiceState("greetd")
	if err != nil {
		return fmt.Errorf("failed to check greetd state: %w", err)
	}

	if !state.Exists {
		return fmt.Errorf("greetd service not found. Please install greetd first")
	}

	fmt.Printf("  Current state: %s\n", state.EnabledState)

	if state.EnabledState == "masked" || state.EnabledState == "masked-runtime" {
		fmt.Println("  Unmasking greetd...")
		if err := privesc.Run(context.Background(), "", "systemctl", "unmask", "greetd"); err != nil {
			return fmt.Errorf("failed to unmask greetd: %w", err)
		}
		fmt.Println("  ✓ Unmasked greetd")
	}

	if state.EnabledState == "enabled" || state.EnabledState == "enabled-runtime" {
		fmt.Println("  Reasserting greetd as active display manager...")
	} else {
		fmt.Println("  Enabling greetd service...")
	}

	if err := privesc.Run(context.Background(), "", "systemctl", "enable", "--force", "greetd"); err != nil {
		return fmt.Errorf("failed to enable greetd: %w", err)
	}

	enabledState, _, verifyErr := checkSystemdServiceEnabled("greetd")
	if verifyErr != nil {
		fmt.Printf("  ⚠ Warning: Could not verify greetd enabled state: %v\n", verifyErr)
		return nil
	}

	switch enabledState {
	case "enabled", "enabled-runtime", "static", "indirect", "alias":
		fmt.Printf("  ✓ greetd enabled (state: %s)\n", enabledState)
		return nil
	default:
		return fmt.Errorf("greetd is still in state '%s' after enable operation", enabledState)
	}
}

func ensureGraphicalTarget() error {
	if isRunit() {
		// runit has no targets; a supervised greetd service is the graphical
		// login, so there is nothing to set here.
		return nil
	}

	getDefaultCmd := exec.Command("systemctl", "get-default")
	currentTarget, err := getDefaultCmd.Output()
	if err != nil {
		fmt.Println("⚠ Warning: Could not detect current default systemd target")
		return nil
	}

	currentTargetStr := strings.TrimSpace(string(currentTarget))
	if currentTargetStr == "graphical.target" {
		fmt.Println("✓ Default target already set to graphical.target")
		return nil
	}

	fmt.Printf("\nSetting graphical.target as default (current: %s)...\n", currentTargetStr)
	if err := privesc.Run(context.Background(), "", "systemctl", "set-default", "graphical.target"); err != nil {
		fmt.Println("⚠ Warning: Failed to set graphical.target as default")
		fmt.Println("  Greeter may not start on boot. Run manually:")
		fmt.Println("  sudo systemctl set-default graphical.target")
		return nil
	}
	fmt.Println("✓ Set graphical.target as default")

	return nil
}
