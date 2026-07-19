// Package launcher replaces the historical dms-greeter bash wrapper: it
// prepares the greeter environment, generates a per-compositor config that
// spawns quickshell, and runs the compositor under greetd supervision.
package launcher

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const DefaultCacheDir = "/var/cache/dms-greeter"

type Options struct {
	Compositor          string
	CompositorConfig    string
	ShellDir            string
	CacheDir            string
	RememberLastSession string
	RememberLastUser    string
	Debug               bool
}

func NormalizeBool(flagName, value string) (string, error) {
	switch strings.ToLower(value) {
	case "1", "true", "yes", "on":
		return "1", nil
	case "0", "false", "no", "off":
		return "0", nil
	default:
		return "", fmt.Errorf("%s must be true/false (or 1/0, yes/no, on/off)", flagName)
	}
}

// LocateShellConfig resolves a named quickshell config the way the bash
// wrapper did: XDG_CONFIG_HOME, /usr/share/quickshell, then XDG_CONFIG_DIRS.
func LocateShellConfig(name string) (string, error) {
	if filepath.IsAbs(name) {
		return name, nil
	}

	var searchPaths []string
	configHome := os.Getenv("XDG_CONFIG_HOME")
	if configHome == "" {
		configHome = filepath.Join(os.Getenv("HOME"), ".config")
	}
	searchPaths = append(searchPaths, filepath.Join(configHome, "quickshell", name))
	searchPaths = append(searchPaths, filepath.Join("/usr/share/quickshell", name))

	configDirs := os.Getenv("XDG_CONFIG_DIRS")
	if configDirs == "" {
		configDirs = "/etc/xdg"
	}
	for dir := range strings.SplitSeq(configDirs, ":") {
		if dir == "" {
			continue
		}
		searchPaths = append(searchPaths, filepath.Join(dir, "quickshell", name))
	}

	for _, path := range searchPaths {
		info, err := os.Stat(filepath.Join(path, "shell.qml"))
		if err != nil || info.IsDir() {
			continue
		}
		return path, nil
	}
	return "", fmt.Errorf("could not find quickshell config %q (shell.qml) in any config path", name)
}

func Run(opts Options) error {
	if opts.Compositor == "" {
		return fmt.Errorf("--command COMPOSITOR is required")
	}

	info, err := os.Stat(opts.CacheDir)
	if err != nil || !info.IsDir() {
		return fmt.Errorf("cache directory %q does not exist.\n  Run 'dms-greeter sync' to initialize it, or pass --cache-dir to an existing directory", opts.CacheDir)
	}

	if err := setupEnvironment(opts); err != nil {
		return err
	}

	qsBin, err := resolveQuickshellBinary()
	if err != nil {
		return err
	}
	qsCmd := fmt.Sprintf("%s -p %s", qsBin, opts.ShellDir)

	plan, err := buildPlan(opts.Compositor, opts.CompositorConfig, qsCmd)
	if err != nil {
		return err
	}
	return execCompositor(plan, opts.CacheDir, opts.Debug)
}

func setupEnvironment(opts Options) error {
	env := map[string]string{
		"XDG_SESSION_TYPE":                    "wayland",
		"QT_QPA_PLATFORM":                     "wayland",
		"QT_WAYLAND_DISABLE_WINDOWDECORATION": "1",
		"EGL_PLATFORM":                        "gbm",
		"DMS_RUN_GREETER":                     "1",
		"DMS_GREET_CFG_DIR":                   opts.CacheDir,
		"HOME":                                opts.CacheDir,
		"XDG_STATE_HOME":                      filepath.Join(opts.CacheDir, ".local/state"),
		"XDG_DATA_HOME":                       filepath.Join(opts.CacheDir, ".local/share"),
		"XDG_CACHE_HOME":                      filepath.Join(opts.CacheDir, ".cache"),
	}
	for key, value := range env {
		if err := os.Setenv(key, value); err != nil {
			return err
		}
	}

	if err := exportRememberFlag(opts.RememberLastSession, "DMS_GREET_REMEMBER_LAST_SESSION", "DMS_SAVE_SESSION"); err != nil {
		return err
	}
	if err := exportRememberFlag(opts.RememberLastUser, "DMS_GREET_REMEMBER_LAST_USER", "DMS_SAVE_USERNAME"); err != nil {
		return err
	}

	// Fallback runtime dir for systems without logind/pam_rundir (e.g.
	// Void+seatd), where Wayland compositors abort with "RuntimeDirNotSet".
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	if runtimeDir == "" || !isDir(runtimeDir) {
		fallback := filepath.Join(opts.CacheDir, "run")
		if err := os.MkdirAll(fallback, 0o700); err != nil {
			return err
		}
		if err := os.Chmod(fallback, 0o700); err != nil {
			return err
		}
		if err := os.Setenv("XDG_RUNTIME_DIR", fallback); err != nil {
			return err
		}
	}

	setEnvDefault("RUST_LOG", "warn")
	setEnvDefault("NIRI_LOG", "warn")

	applyUserCursor(filepath.Join(opts.CacheDir, "settings.json"))
	return nil
}

func exportRememberFlag(value, rememberVar, saveVar string) error {
	if value == "" {
		return nil
	}
	if err := os.Setenv(rememberVar, value); err != nil {
		return err
	}
	saveValue := "false"
	if value == "1" {
		saveValue = "true"
	}
	return os.Setenv(saveVar, saveValue)
}

func resolveQuickshellBinary() (string, error) {
	for _, candidate := range []string{"qs", "quickshell"} {
		if _, err := exec.LookPath(candidate); err == nil {
			return candidate, nil
		}
	}
	return "", fmt.Errorf("neither 'qs' nor 'quickshell' was found in PATH")
}

func setEnvDefault(key, value string) {
	if os.Getenv(key) != "" {
		return
	}
	os.Setenv(key, value)
}

func isDir(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}
