package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"

	"github.com/AvengeMedia/dank-greeter/core/internal/greeter"
	sharedpam "github.com/AvengeMedia/dank-greeter/core/internal/pam"
	"github.com/AvengeMedia/dank-greeter/core/internal/privesc"
	"github.com/AvengeMedia/dank-greeter/core/internal/utils"
)

func runCommandInTerminal(shellCmd string) error {
	terminals := []struct {
		name string
		args []string
	}{
		{"gnome-terminal", []string{"--", "bash", "-c", shellCmd}},
		{"konsole", []string{"-e", "bash", "-c", shellCmd}},
		{"xfce4-terminal", []string{"-e", "bash -c \"" + strings.ReplaceAll(shellCmd, `"`, `\"`) + "\""}},
		{"ghostty", []string{"-e", "bash", "-c", shellCmd}},
		{"wezterm", []string{"start", "--", "bash", "-c", shellCmd}},
		{"alacritty", []string{"-e", "bash", "-c", shellCmd}},
		{"kitty", []string{"bash", "-c", shellCmd}},
		{"xterm", []string{"-e", "bash -c \"" + strings.ReplaceAll(shellCmd, `"`, `\"`) + "\""}},
	}
	for _, t := range terminals {
		if _, err := exec.LookPath(t.name); err != nil {
			continue
		}
		cmd := exec.Command(t.name, t.args...)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		return cmd.Run()
	}
	return fmt.Errorf("no terminal emulator found (tried: gnome-terminal, konsole, xfce4-terminal, ghostty, wezterm, alacritty, kitty, xterm)")
}

func syncInTerminal(nonInteractive bool, forceAuth bool, local bool, profileOnly bool, autologinOnly bool) error {
	syncFlags := make([]string, 0, 5)
	if nonInteractive {
		syncFlags = append(syncFlags, "--yes")
	}
	if forceAuth {
		syncFlags = append(syncFlags, "--auth")
	}
	if local {
		syncFlags = append(syncFlags, "--local")
	}
	if profileOnly {
		syncFlags = append(syncFlags, "--profile")
	}
	if autologinOnly {
		syncFlags = append(syncFlags, "--autologin")
	}
	shellSyncCmd := "dms-greeter sync"
	if len(syncFlags) > 0 {
		shellSyncCmd += " " + strings.Join(syncFlags, " ")
	}
	var shellCmd string
	if autologinOnly {
		shellCmd = shellSyncCmd + `; echo; echo "Auto-login update finished. Closing in 3 seconds..."; sleep 3`
	} else {
		shellCmd = shellSyncCmd + `; echo; echo "Sync finished. Closing in 3 seconds..."; sleep 3`
	}
	return runCommandInTerminal(shellCmd)
}

func syncGreeterAutoLoginOnly() error {
	logFunc := func(msg string) {
		fmt.Println(msg)
	}

	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("failed to get user home directory: %w", err)
	}

	settingsPath := filepath.Join(homeDir, ".config", "DankMaterialShell", "settings.json")
	cacheSettingsPath := filepath.Join(greeter.GreeterCacheDir, "settings.json")
	enabled := false
	for _, path := range []string{cacheSettingsPath, settingsPath} {
		data, readErr := os.ReadFile(path)
		if readErr != nil {
			continue
		}
		var cfg struct {
			GreeterAutoLogin bool `json:"greeterAutoLogin"`
		}
		if json.Unmarshal(data, &cfg) == nil {
			enabled = cfg.GreeterAutoLogin
			break
		}
	}

	fmt.Println("=== Greeter Auto-Login ===")
	fmt.Println()
	if enabled {
		fmt.Println("Enabling auto-login on startup in greetd.")
		fmt.Println("After your next reboot, DMS will skip the greeter password until you sign out.")
	} else {
		fmt.Println("Disabling auto-login on startup in greetd.")
		fmt.Println("After your next reboot, you will enter your password at the greeter again.")
	}
	fmt.Println()
	fmt.Println("Administrator (sudo) access is required to update /etc/greetd/config.toml.")
	fmt.Println()

	return greeter.SyncGreeterAutoLoginOnly(logFunc, "")
}

func syncGreeter(nonInteractive bool, forceAuth bool, local bool, profileOnly bool) error {
	if profileOnly {
		return syncGreeterProfileOnly(nonInteractive)
	}

	if !nonInteractive {
		fmt.Println("=== DMS Greeter Sync ===")
		fmt.Println()
	}

	logFunc := func(msg string) {
		fmt.Println(msg)
	}

	var localCheckout *localGreeterCheckout
	if local {
		checkout, err := resolveLocalGreeterCheckout()
		if err != nil {
			return err
		}
		localCheckout = &checkout
		if !nonInteractive {
			fmt.Printf("✓ Using local greeter checkout: %s\n", checkout.rootDir)
		}
	}

	if !isGreeterEnabled() {
		if nonInteractive {
			return fmt.Errorf("greeter is not enabled; run 'dms-greeter install' or 'dms-greeter enable' first")
		}
		fmt.Println("\n⚠ DMS greeter is not enabled in greetd config.")
		fmt.Print("Would you like to enable it now? (Y/n): ")

		var response string
		fmt.Scanln(&response)
		response = strings.ToLower(strings.TrimSpace(response))

		if response == "n" || response == "no" {
			return fmt.Errorf("greeter must be enabled before syncing")
		}
		if err := enableGreeter(false); err != nil {
			return err
		}
	}

	if err := rejectLegacyWrapper(); err != nil {
		return err
	}

	cacheDir := greeter.GreeterCacheDir
	if _, err := os.Stat(cacheDir); os.IsNotExist(err) {
		logFunc("Cache directory not found — attempting to create it...")
	}

	greeterGroup := greeter.DetectGreeterGroup()
	if utils.HasGroup(greeterGroup) {
		currentUser, err := user.Current()
		if err != nil {
			return fmt.Errorf("failed to get current user: %w", err)
		}

		groupsCmd := exec.Command("groups", currentUser.Username)
		groupsOutput, err := groupsCmd.Output()
		if err != nil {
			return fmt.Errorf("failed to check groups: %w", err)
		}

		inGreeterGroup := strings.Contains(string(groupsOutput), greeterGroup)
		switch {
		case inGreeterGroup:
		case nonInteractive:
			logFunc(fmt.Sprintf("⚠ Not yet in %s group — will be added during sync (logout/login required to take effect).", greeterGroup))
		default:
			fmt.Printf("\n⚠ Warning: You are not in the %s group.\n", greeterGroup)
			fmt.Printf("Would you like to add your user to the %s group? (Y/n): ", greeterGroup)

			var response string
			fmt.Scanln(&response)
			response = strings.ToLower(strings.TrimSpace(response))

			if response == "n" || response == "no" {
				return fmt.Errorf("aborted: user must be in the greeter group before syncing")
			}
			fmt.Printf("\nAdding user to %s group...\n", greeterGroup)
			if err := privesc.Run(context.Background(), "", "usermod", "-aG", greeterGroup, currentUser.Username); err != nil {
				return fmt.Errorf("failed to add user to %s group: %w", greeterGroup, err)
			}
			fmt.Printf("✓ User added to %s group\n", greeterGroup)
			fmt.Println("⚠ You will need to log out and back in for the group change to take effect")
		}
	}

	compositor := detectConfiguredCompositor()
	if compositor == "" {
		compositors := greeter.DetectCompositors()
		switch len(compositors) {
		case 0:
			return fmt.Errorf("no supported compositors found")
		case 1:
			compositor = compositors[0]
			if !nonInteractive {
				fmt.Printf("✓ Using compositor: %s\n", compositor)
			}
		default:
			if nonInteractive {
				compositor = compositors[0]
				break
			}
			var err error
			compositor, err = promptCompositorChoice(compositors)
			if err != nil {
				return err
			}
			fmt.Printf("✓ Selected compositor: %s\n", compositor)
		}
	} else if !nonInteractive {
		fmt.Printf("✓ Detected compositor from config: %s\n", compositor)
	}

	if local {
		fmt.Println("\nBuilding local greeter (Go + embedded QML)...")
		localBinary, err := buildAndInstallLocalGreeter(*localCheckout, logFunc, "", defaultLocalGreeterBuildDeps())
		if err != nil {
			return err
		}
		if err := greeter.ConfigureGreetdWithBinary(localBinary, "", compositor, logFunc, ""); err != nil {
			return fmt.Errorf("failed to apply local greeter binary: %w", err)
		}
		if !nonInteractive {
			fmt.Printf("ℹ Local mode uses %s, built from this checkout with its QML embedded.\n", localBinary)
			fmt.Println("ℹ Run dms-greeter sync (without --local) to switch greetd back to the packaged binary.")
		}
	} else {
		fmt.Println("\nUpdating greetd command...")
		if err := greeter.ConfigureGreetd("", compositor, logFunc, ""); err != nil {
			return fmt.Errorf("failed to update greetd command: %w", err)
		}
	}

	fmt.Println("\nSetting up permissions and ACLs...")
	greeter.RemediateStaleACLs(logFunc, "")
	greeter.RemediateStaleAppArmor(logFunc, "")
	if err := greeter.SetupDMSGroup(logFunc, ""); err != nil {
		return err
	}
	if err := greeter.EnsureGreeterCacheDir(logFunc, ""); err != nil {
		return fmt.Errorf("failed to ensure greeter cache directory at %s: %w", cacheDir, err)
	}

	fmt.Println("\nSynchronizing DMS configurations...")
	if err := syncGreeterConfigsAndAuth(compositor, logFunc, sharedpam.SyncAuthOptions{
		ForceGreeterAuth: forceAuth,
	}, func() {
		fmt.Println("\nConfiguring authentication...")
	}); err != nil {
		return err
	}

	if greeter.IsAppArmorEnabled() {
		fmt.Println("\nConfiguring AppArmor profile...")
		if err := greeter.InstallAppArmorProfile(logFunc, ""); err != nil {
			logFunc(fmt.Sprintf("⚠ AppArmor profile setup failed: %v", err))
		}
	}

	fmt.Println("\n=== Sync Complete ===")
	fmt.Println("\nYour theme, settings, and wallpaper configuration have been synced with the greeter.")
	fmt.Println("Shared authentication settings were also checked and reconciled where needed.")
	if forceAuth {
		fmt.Println("Authentication has been configured for fingerprint and U2F (where modules exist).")
	}
	fmt.Println("The changes will be visible on the next login screen.")

	return nil
}

func syncGreeterProfileOnly(nonInteractive bool) error {
	logFunc := func(msg string) {
		fmt.Println(msg)
	}
	if !nonInteractive {
		fmt.Println("=== DMS Greeter Profile Sync ===")
		fmt.Println()
		fmt.Println("Syncing your personal greeter theme slot (no system changes)...")
	}
	if err := greeter.SyncUserProfileCache(logFunc); err != nil {
		return err
	}
	if !nonInteractive {
		fmt.Println("\n=== Profile Sync Complete ===")
		fmt.Println("\nYour theme, wallpaper, and profile photo have been synced for the login screen.")
		fmt.Println("Log out to preview your greeter look when selecting your account.")
	}
	return nil
}

func rejectLegacyWrapper() error {
	paths := greeter.LegacyWrapperScriptPaths()
	if len(paths) == 0 {
		return nil
	}
	return fmt.Errorf("legacy dms-greeter shell wrapper detected at %s\nRemove the old wrapper (or the old dms-greeter package) before using this binary: sudo rm -f %s", strings.Join(paths, ", "), strings.Join(paths, " "))
}

type localGreeterCheckout struct {
	rootDir  string
	shellDir string
}

func hasLocalGreeterSource(rootDir string) bool {
	for _, path := range []string{
		filepath.Join(rootDir, "core", "go.mod"),
		filepath.Join(rootDir, "core", "Makefile"),
		filepath.Join(rootDir, "quickshell", "shell.qml"),
	} {
		info, err := os.Stat(path)
		if err != nil || info.IsDir() {
			return false
		}
	}
	return true
}

func resolveLocalCheckoutCandidate(path string) (localGreeterCheckout, bool) {
	if path == "" {
		return localGreeterCheckout{}, false
	}

	abs, err := filepath.Abs(path)
	if err != nil {
		abs = path
	}

	for dir := abs; ; dir = filepath.Dir(dir) {
		if hasLocalGreeterSource(dir) {
			return localGreeterCheckout{
				rootDir:  dir,
				shellDir: filepath.Join(dir, "quickshell"),
			}, true
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
	}

	return localGreeterCheckout{}, false
}

// resolveLocalGreeterCheckout finds a source tree containing both the Go
// launcher and the QML that `sync --local` embeds in its development binary.
func resolveLocalGreeterCheckout() (localGreeterCheckout, error) {
	if override := strings.TrimSpace(os.Getenv("DMS_LOCAL_PATH")); override != "" {
		if resolved, ok := resolveLocalCheckoutCandidate(override); ok {
			return resolved, nil
		}
		return localGreeterCheckout{}, fmt.Errorf("DMS_LOCAL_PATH is set but does not point to a complete dank-greeter checkout: %s", override)
	}

	wd, err := os.Getwd()
	if err != nil {
		return localGreeterCheckout{}, fmt.Errorf("failed to get current directory: %w", err)
	}

	dir := wd
	for {
		if resolved, ok := resolveLocalCheckoutCandidate(dir); ok {
			return resolved, nil
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}

	homeDir, err := os.UserHomeDir()
	if err == nil && homeDir != "" {
		for _, candidate := range []string{
			filepath.Join(homeDir, "dank-greeter"),
			filepath.Join(homeDir, "projects", "dank-greeter"),
			filepath.Join(homeDir, "src", "dank-greeter"),
			filepath.Join(homeDir, "repos", "dank-greeter"),
		} {
			if resolved, ok := resolveLocalCheckoutCandidate(candidate); ok {
				return resolved, nil
			}
		}

		if entries, readErr := os.ReadDir(homeDir); readErr == nil {
			for _, entry := range entries {
				if !entry.IsDir() {
					continue
				}
				name := strings.ToLower(entry.Name())
				if !strings.Contains(name, "dms") && !strings.Contains(name, "dank") {
					continue
				}
				if resolved, ok := resolveLocalCheckoutCandidate(filepath.Join(homeDir, entry.Name())); ok {
					return resolved, nil
				}
			}
		}
	}

	configuredCommand := readDefaultSessionCommand("/etc/greetd/config.toml")
	if pathOverride := extractGreeterShellDirFromCommand(configuredCommand); pathOverride != "" {
		if resolved, ok := resolveLocalCheckoutCandidate(pathOverride); ok {
			return resolved, nil
		}
	}

	return localGreeterCheckout{}, fmt.Errorf("could not locate a complete dank-greeter checkout from %s; run from the repo or set DMS_LOCAL_PATH=/absolute/path/to/dank-greeter", wd)
}

type localGreeterBuildDeps struct {
	commandExists func(string) bool
	runBuild      func(string, string, ...string) error
	install       func(string, func(string), string) (string, error)
}

func defaultLocalGreeterBuildDeps() localGreeterBuildDeps {
	return localGreeterBuildDeps{
		commandExists: utils.CommandExists,
		runBuild: func(dir, command string, args ...string) error {
			cmd := exec.Command(command, args...)
			cmd.Dir = dir
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			return cmd.Run()
		},
		install: greeter.InstallLocalGreeterBinary,
	}
}

func buildAndInstallLocalGreeter(checkout localGreeterCheckout, logFunc func(string), sudoPassword string, deps localGreeterBuildDeps) (string, error) {
	for _, command := range []string{"make", "go", "tar"} {
		if !deps.commandExists(command) {
			return "", fmt.Errorf("cannot build local greeter: required command %q is not installed", command)
		}
	}

	commonMarker := filepath.Join(checkout.shellDir, "DankCommon", "Widgets", "DankIcon.qml")
	if info, err := os.Stat(commonMarker); err != nil || info.IsDir() {
		return "", fmt.Errorf("dank-qml-common is missing from %s; run 'git submodule update --init dank-qml-common' in the checkout", checkout.rootDir)
	}

	coreDir := filepath.Join(checkout.rootDir, "core")
	if err := deps.runBuild(coreDir, "make", "build", "BINARY_NAME=dms-greeter-local"); err != nil {
		return "", fmt.Errorf("failed to build local greeter from %s: %w", checkout.rootDir, err)
	}

	builtBinary := filepath.Join(coreDir, "bin", "dms-greeter-local")
	info, err := os.Stat(builtBinary)
	if err != nil {
		return "", fmt.Errorf("local greeter build did not produce %s: %w", builtBinary, err)
	}
	if info.IsDir() || info.Mode()&0o111 == 0 {
		return "", fmt.Errorf("local greeter build output is not executable: %s", builtBinary)
	}

	installedPath, err := deps.install(builtBinary, logFunc, sudoPassword)
	if err != nil {
		return "", err
	}
	return installedPath, nil
}

func promptCompositorChoice(compositors []string) (string, error) {
	fmt.Println("\nMultiple compositors detected:")
	for i, comp := range compositors {
		fmt.Printf("%d) %s\n", i+1, comp)
	}

	var response string
	fmt.Print("Choose compositor for greeter: ")
	fmt.Scanln(&response)
	response = strings.TrimSpace(response)

	choice := 0
	fmt.Sscanf(response, "%d", &choice)

	if choice < 1 || choice > len(compositors) {
		return "", fmt.Errorf("invalid choice")
	}

	return compositors[choice-1], nil
}
