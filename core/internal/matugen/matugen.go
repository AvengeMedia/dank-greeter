// Package matugen generates the greeter's dms-colors.json from a wallpaper
// image via the matugen CLI, injecting the dank16 palette. It is the
// colors-only slice of the DMS matugen pipeline; the dank.json template is
// embedded so no DMS quickshell tree is required.
package matugen

import (
	"bytes"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/AvengeMedia/dank-greeter/core/internal/dank16"
	"github.com/AvengeMedia/dank-greeter/core/internal/utils"
	log "github.com/AvengeMedia/dankgo/log"
)

var ErrNoChanges = errors.New("no color changes")

type ColorMode string

const (
	ColorModeDark  ColorMode = "dark"
	ColorModeLight ColorMode = "light"
)

//go:embed templates/dank.json
var dankColorsTemplate []byte

var (
	matugenVersionMu   sync.Mutex
	matugenVersionOK   bool
	matugenSupportsCOE bool
	matugenIsV4        bool
)

type Options struct {
	StateDir    string
	Kind        string
	Value       string
	Mode        ColorMode
	MatugenType string
}

func (o *Options) ColorsOutput() string {
	return filepath.Join(o.StateDir, "dms-colors.json")
}

func (o *Options) colorsStaging() string {
	return o.ColorsOutput() + ".tmp"
}

func acquireMatugenLock(stateDir string) (*os.File, error) {
	f, err := os.OpenFile(filepath.Join(stateDir, "matugen.lock"), os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, fmt.Errorf("failed to open matugen lock: %w", err)
	}

	deadline := time.Now().Add(45 * time.Second)
	for {
		switch err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err {
		case nil:
			return f, nil
		case syscall.EWOULDBLOCK:
			if time.Now().After(deadline) {
				f.Close()
				return nil, fmt.Errorf("timed out waiting for matugen lock")
			}
			time.Sleep(100 * time.Millisecond)
		default:
			f.Close()
			return nil, fmt.Errorf("failed to lock matugen: %w", err)
		}
	}
}

func releaseMatugenLock(f *os.File) {
	if f == nil {
		return
	}
	_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	f.Close()
}

func Run(opts Options) error {
	if opts.StateDir == "" {
		return fmt.Errorf("state-dir is required")
	}
	if opts.Kind == "" {
		return fmt.Errorf("kind is required")
	}
	if opts.Value == "" {
		return fmt.Errorf("value is required")
	}
	if opts.Mode == "" {
		opts.Mode = ColorModeDark
	}
	if opts.MatugenType == "" {
		opts.MatugenType = "scheme-tonal-spot"
	}

	if err := os.MkdirAll(opts.StateDir, 0o755); err != nil {
		return fmt.Errorf("failed to create state dir: %w", err)
	}

	lock, err := acquireMatugenLock(opts.StateDir)
	if err != nil {
		return err
	}
	defer releaseMatugenLock(lock)

	log.Infof("Building greeter colors: %s %s (%s)", opts.Kind, opts.Value, opts.Mode)

	changed, buildErr := buildOnce(&opts)
	if buildErr != nil {
		return buildErr
	}
	if !changed {
		log.Info("No color changes detected")
		return ErrNoChanges
	}
	return nil
}

func buildOnce(opts *Options) (bool, error) {
	defer os.Remove(opts.colorsStaging())

	tmpDir, err := os.MkdirTemp("", "dms-greeter-matugen-*")
	if err != nil {
		return false, fmt.Errorf("failed to create temp dir: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	templatePath := filepath.Join(tmpDir, "dank.json")
	if err := os.WriteFile(templatePath, dankColorsTemplate, 0o644); err != nil {
		return false, fmt.Errorf("failed to write colors template: %w", err)
	}

	cfgPath := filepath.Join(tmpDir, "config.toml")
	cfg := fmt.Sprintf("[config]\n\n[templates.dank]\ninput_path = '%s'\noutput_path = '%s'\n", templatePath, opts.colorsStaging())
	if err := os.WriteFile(cfgPath, []byte(cfg), 0o644); err != nil {
		return false, fmt.Errorf("failed to write matugen config: %w", err)
	}

	oldColors, _ := os.ReadFile(opts.ColorsOutput())

	matJSON, err := runMatugenDryRun(opts)
	if err != nil {
		return false, fmt.Errorf("matugen dry-run failed: %w", err)
	}

	primaryDark := extractMatugenColor(matJSON, "primary", "dark")
	primaryLight := extractMatugenColor(matJSON, "primary", "light")
	surface := extractMatugenColor(matJSON, "surface", "dark")
	if primaryDark == "" {
		return false, fmt.Errorf("failed to extract primary color")
	}
	if primaryLight == "" {
		primaryLight = primaryDark
	}

	importData := fmt.Sprintf(`{"dank16": %s}`, generateDank16Variants(primaryDark, primaryLight, surface, opts.Mode))

	var args []string
	switch opts.Kind {
	case "hex":
		args = []string{"color", "hex", opts.Value}
	default:
		args = []string{opts.Kind, opts.Value}
	}
	args = append(args, "-m", string(opts.Mode), "-t", opts.MatugenType, "-c", cfgPath, "--import-json-string", importData)
	if err := runMatugen(args); err != nil {
		return false, err
	}

	newColors, err := os.ReadFile(opts.colorsStaging())
	if err != nil {
		return false, fmt.Errorf("matugen did not produce colors output: %w", err)
	}
	if bytes.Equal(oldColors, newColors) && len(oldColors) > 0 {
		return false, nil
	}
	if err := os.Rename(opts.colorsStaging(), opts.ColorsOutput()); err != nil {
		return false, fmt.Errorf("failed to commit colors output: %w", err)
	}
	return true, nil
}

type matugenFlags struct {
	supportsCOE bool
	isV4        bool
}

func detectMatugenVersion() (matugenFlags, error) {
	matugenVersionMu.Lock()
	defer matugenVersionMu.Unlock()

	if matugenVersionOK {
		return matugenFlags{matugenSupportsCOE, matugenIsV4}, nil
	}
	return detectMatugenVersionLocked()
}

func redetectMatugenVersion(old matugenFlags) (matugenFlags, bool) {
	matugenVersionMu.Lock()
	defer matugenVersionMu.Unlock()

	matugenVersionOK = false
	flags, err := detectMatugenVersionLocked()
	if err != nil {
		return old, false
	}
	changed := flags.supportsCOE != old.supportsCOE || flags.isV4 != old.isV4
	return flags, changed
}

func detectMatugenVersionLocked() (matugenFlags, error) {
	cmd := exec.Command("matugen", "--version")
	cmd.Env = utils.EnvWithUserBinPath(nil)
	output, err := cmd.Output()
	if err != nil {
		return matugenFlags{}, fmt.Errorf("failed to get matugen version: %w", err)
	}

	versionStr := strings.TrimSpace(string(output))
	versionStr = strings.TrimPrefix(versionStr, "matugen ")

	parts := strings.Split(versionStr, ".")
	if len(parts) < 2 {
		return matugenFlags{}, fmt.Errorf("unexpected matugen version format: %q", versionStr)
	}

	major, err := strconv.Atoi(parts[0])
	if err != nil {
		return matugenFlags{}, fmt.Errorf("failed to parse matugen major version %q: %w", parts[0], err)
	}
	minor, err := strconv.Atoi(parts[1])
	if err != nil {
		return matugenFlags{}, fmt.Errorf("failed to parse matugen minor version %q: %w", parts[1], err)
	}

	matugenSupportsCOE = major > 3 || (major == 3 && minor >= 1)
	matugenIsV4 = major >= 4
	matugenVersionOK = true
	return matugenFlags{matugenSupportsCOE, matugenIsV4}, nil
}

func buildMatugenArgs(baseArgs []string, flags matugenFlags) []string {
	args := make([]string, 0, len(baseArgs)+3)
	if flags.supportsCOE {
		args = append(args, "--continue-on-error")
	}
	args = append(args, baseArgs...)
	if flags.isV4 {
		args = append(args, "--source-color-index", "0")
	}
	return args
}

func runMatugen(baseArgs []string) error {
	flags, err := detectMatugenVersion()
	if err != nil {
		return err
	}

	args := buildMatugenArgs(baseArgs, flags)
	cmd := exec.Command("matugen", args...)
	cmd.Env = utils.EnvWithUserBinPath(nil)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	runErr := cmd.Run()
	if runErr == nil {
		return nil
	}

	log.Warnf("Matugen failed (v4=%v): %v", flags.isV4, runErr)

	newFlags, changed := redetectMatugenVersion(flags)
	if !changed {
		return runErr
	}

	log.Warnf("Matugen version changed (v4: %v -> %v), retrying", flags.isV4, newFlags.isV4)
	args = buildMatugenArgs(baseArgs, newFlags)
	retryCmd := exec.Command("matugen", args...)
	retryCmd.Env = utils.EnvWithUserBinPath(nil)
	retryCmd.Stdout = os.Stdout
	retryCmd.Stderr = os.Stderr
	return retryCmd.Run()
}

func runMatugenDryRun(opts *Options) (string, error) {
	flags, err := detectMatugenVersion()
	if err != nil {
		return "", err
	}

	output, dryErr := execDryRun(opts, flags)
	if dryErr == nil {
		return output, nil
	}

	log.Warnf("Matugen dry-run failed (v4=%v): %v", flags.isV4, dryErr)

	newFlags, changed := redetectMatugenVersion(flags)
	if !changed {
		return "", dryErr
	}

	log.Warnf("Matugen version changed (v4: %v -> %v), retrying dry-run", flags.isV4, newFlags.isV4)
	return execDryRun(opts, newFlags)
}

func execDryRun(opts *Options, flags matugenFlags) (string, error) {
	var baseArgs []string
	switch opts.Kind {
	case "hex":
		baseArgs = []string{"color", "hex", opts.Value}
	default:
		baseArgs = []string{opts.Kind, opts.Value}
	}
	baseArgs = append(baseArgs, "-m", "dark", "-t", opts.MatugenType, "--json", "hex", "--dry-run")
	if flags.isV4 {
		baseArgs = append(baseArgs, "--source-color-index", "0", "--old-json-output")
	}

	cmd := exec.Command("matugen", baseArgs...)
	cmd.Env = utils.EnvWithUserBinPath(nil)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	output, err := cmd.Output()
	if err != nil {
		if stderr.Len() > 0 {
			return "", fmt.Errorf("matugen %v failed (v4=%v): %s", baseArgs, flags.isV4, strings.TrimSpace(stderr.String()))
		}
		return "", fmt.Errorf("matugen %v failed (v4=%v): %w", baseArgs, flags.isV4, err)
	}
	return strings.ReplaceAll(string(output), "\n", ""), nil
}

func extractMatugenColor(jsonStr, colorName, variant string) string {
	var data map[string]any
	if err := json.Unmarshal([]byte(jsonStr), &data); err != nil {
		return ""
	}

	colors, ok := data["colors"].(map[string]any)
	if !ok {
		return ""
	}
	colorData, ok := colors[colorName].(map[string]any)
	if !ok {
		return ""
	}
	variantData, ok := colorData[variant].(string)
	if !ok {
		return ""
	}
	return variantData
}

func generateDank16Variants(primaryDark, primaryLight, surface string, mode ColorMode) string {
	variantColors := dank16.GenerateVariantPalette(dank16.VariantOptions{
		PrimaryDark:  primaryDark,
		PrimaryLight: primaryLight,
		Background:   surface,
		UseDPS:       true,
		IsLightMode:  mode == ColorModeLight,
	})
	return dank16.GenerateVariantJSON(variantColors)
}
