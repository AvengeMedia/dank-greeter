package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/AvengeMedia/dank-greeter/core/internal/launcher"
	"github.com/AvengeMedia/dank-greeter/core/internal/shellembed"
	"github.com/spf13/cobra"
)

var launchFlags struct {
	compositor          string
	compositorConfig    string
	legacyShellPath     string
	cacheDir            string
	rememberLastSession string
	rememberLastUser    string
	noSaveSession       bool
	noSaveUsername      bool
	debug               bool
}

var rootCmd = &cobra.Command{
	Use:   "dms-greeter",
	Short: "DMS Greeter",
	Long:  "DMS Greeter - a greetd login screen with the Dank Material aesthetic.\n\nInvoked from greetd as: dms-greeter --command COMPOSITOR",
	Args:  cobra.NoArgs,
	RunE:  runGreeter,
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Show version information",
	RunE: func(_ *cobra.Command, _ []string) error {
		fmt.Printf("dms-greeter %s (commit %s, built %s)\n", Version, Commit, BuildTime)
		return nil
	},
}

func runGreeter(cmd *cobra.Command, _ []string) error {
	if launchFlags.compositor == "" {
		_ = cmd.Help()
		return fmt.Errorf("--command COMPOSITOR is required")
	}

	if !isDirectory(launchFlags.cacheDir) {
		return fmt.Errorf("cache directory %q does not exist.\n  Run 'dms-greeter sync' to initialize it, or pass --cache-dir to an existing directory", launchFlags.cacheDir)
	}

	rememberSession, err := normalizeRememberFlag("--remember-last-session", launchFlags.rememberLastSession, launchFlags.noSaveSession)
	if err != nil {
		return err
	}
	rememberUser, err := normalizeRememberFlag("--remember-last-user", launchFlags.rememberLastUser, launchFlags.noSaveUsername)
	if err != nil {
		return err
	}

	shellDir, err := resolveLaunchShellDir(cmd)
	if err != nil {
		return err
	}

	return launcher.Run(launcher.Options{
		Compositor:          launchFlags.compositor,
		CompositorConfig:    launchFlags.compositorConfig,
		ShellDir:            shellDir,
		CacheDir:            launchFlags.cacheDir,
		RememberLastSession: rememberSession,
		RememberLastUser:    rememberUser,
		Debug:               launchFlags.debug,
	})
}

// resolveLaunchShellDir resolves the quickshell config for the greetd launch
// path: -c/--shell-dir, the legacy -p/--path search, DMS_GREETER_SHELL_DIR,
// then the UI embedded in the binary (extracted under the cache dir, which is
// the only greeter-writable location).
func resolveLaunchShellDir(cmd *cobra.Command) (string, error) {
	if custom := *shellApp.CustomConfigVar(); custom != "" {
		return custom, nil
	}
	if cmd.Flags().Changed("path") {
		return launcher.LocateShellConfig(launchFlags.legacyShellPath)
	}
	if envDir := os.Getenv("DMS_GREETER_SHELL_DIR"); envDir != "" {
		return envDir, nil
	}

	if !shellembed.Available() {
		return "", fmt.Errorf("this build has no embedded UI; pass -c/--shell-dir or -p/--path to a quickshell config dir")
	}
	baseDir := filepath.Join(launchFlags.cacheDir, ".cache", "dms-greeter-shell")
	extracted, err := shellembed.Extract(baseDir)
	if err != nil {
		return "", fmt.Errorf("extracting embedded UI: %w", err)
	}
	shellembed.Prune(baseDir, extracted)
	return extracted, nil
}

func normalizeRememberFlag(flagName, value string, noSaveAlias bool) (string, error) {
	if noSaveAlias {
		return "0", nil
	}
	if value == "" {
		return "", nil
	}
	return launcher.NormalizeBool(flagName, value)
}

func isDirectory(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

func init() {
	rootCmd.PersistentFlags().StringVarP(shellApp.CustomConfigVar(), "shell-dir", "c", "", "Path to a UI config dir (containing shell.qml) to use instead of the embedded UI (env: DMS_GREETER_SHELL_DIR)")

	flags := rootCmd.Flags()
	flags.StringVar(&launchFlags.compositor, "command", "", "Compositor to use (niri, hyprland, sway, scroll, miracle, mango, or labwc)")
	flags.StringVarP(&launchFlags.compositorConfig, "config", "C", "", "Custom compositor config file")
	flags.StringVarP(&launchFlags.legacyShellPath, "path", "p", "", "Quickshell config name or absolute path (deprecated; the embedded UI is the default)")
	flags.StringVar(&launchFlags.cacheDir, "cache-dir", launcher.DefaultCacheDir, "Cache directory for greeter data")
	flags.StringVar(&launchFlags.rememberLastSession, "remember-last-session", "", "Persist selected session to greeter memory (true/false, default: from settings.json)")
	flags.StringVar(&launchFlags.rememberLastUser, "remember-last-user", "", "Persist last successful username to greeter memory (true/false, default: from settings.json)")
	flags.BoolVar(&launchFlags.noSaveSession, "no-save-session", false, "Alias for --remember-last-session false")
	flags.BoolVar(&launchFlags.noSaveUsername, "no-save-username", false, "Alias for --remember-last-user false")
	flags.BoolVar(&launchFlags.debug, "debug", false, "Enable verbose startup logging to stderr")

	rootCmd.AddCommand(versionCmd)
	rootCmd.AddCommand(shellApp.Commands()...)
}
